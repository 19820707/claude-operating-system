#!/usr/bin/env bash
# Autonomous learning loop — anomaly → hypothesis → policy suggestion (human gate). H10: LF-only; exit 0.
set -euo pipefail

echo "[OS-LEARNING-LOOP]"

if ! command -v python3 >/dev/null 2>&1; then
  echo "  skip: python3 not available"
  exit 0
fi

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "  skip: not a git repository"
  exit 0
fi

python3 - "$@" <<'PY'
import json
import subprocess
import sys
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

REPO = Path.cwd().resolve()
IDX = REPO / ".claude" / "session-index.json"
STATE = REPO / ".claude" / "learning-loop-state.json"
REPORT = REPO / ".claude" / "learning-loop-report.json"


def git_text(cmd: list[str]) -> str:
    try:
        return subprocess.check_output(
            cmd, cwd=str(REPO), text=True, stderr=subprocess.DEVNULL
        )
    except subprocess.CalledProcessError:
        return ""


def git_revert_count(module_prefix: str, days: int = 30) -> int:
    spec = module_prefix.rstrip("/") + "/"
    if not (REPO / spec.split("/")[0]).exists():
        return 0
    out = git_text(
        [
            "git",
            "log",
            f"--since={days} days ago",
            "--oneline",
            "-i",
            "--grep=revert",
            "--grep=rollback",
            "--regexp-ignore-case",
            "--",
            spec,
        ]
    )
    return len([l for l in out.splitlines() if l.strip()])


def parse_ts(s: str) -> datetime | None:
    if not s:
        return None
    try:
        if s.endswith("Z"):
            return datetime.fromisoformat(s.replace("Z", "+00:00"))
        return datetime.fromisoformat(s)
    except Exception:
        return None


def load_index() -> dict:
    if not IDX.is_file():
        return {}
    try:
        return json.loads(IDX.read_text(encoding="utf-8"))
    except Exception:
        return {}


def load_state() -> dict:
    if STATE.is_file():
        try:
            return json.loads(STATE.read_text(encoding="utf-8"))
        except Exception:
            pass
    return {"schemaVersion": 1, "next_hypothesis_seq": 1}


def save_state(st: dict):
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(st, indent=2), encoding="utf-8")


def session_text_blob(sess: dict) -> str:
    parts = []
    parts.extend(str(x) for x in (sess.get("risks_opened") or []))
    for d in sess.get("decisions") or []:
        if isinstance(d, dict):
            parts.append(str(d.get("text", "")))
    parts.append(str(sess.get("phase", "")))
    return " ".join(parts).lower()


def main():
    idx = load_index()
    sessions = idx.get("sessions") or []
    now = datetime.now(timezone.utc)
    win14 = now - timedelta(days=14)
    win30 = now - timedelta(days=30)

    recent = []
    for s in sessions:
        ts = parse_ts(s.get("indexed_at") or "") or parse_ts(
            (s.get("id") or "")[:10] + "T00:00:00Z"
        )
        if not ts:
            continue
        if ts.tzinfo is None:
            ts = ts.replace(tzinfo=timezone.utc)
        if ts >= win30:
            recent.append((ts, s))

    recent.sort(key=lambda x: x[0])

    mod_sessions: dict[str, list[dict]] = defaultdict(list)
    mod_signals: dict[str, int] = defaultdict(int)
    for ts, s in recent:
        if ts < win14:
            continue
        for m in s.get("modules_touched") or []:
            if not m or m == ".":
                continue
            mod_sessions[m].append(s)
            if any(
                k in session_text_blob(s)
                for k in ("revert", "rollback", "fail", "ci", "test", "regression")
            ):
                mod_signals[m] += 1

    anomalies = []
    for mod, sess_list in mod_sessions.items():
        if len(sess_list) < 3:
            continue
        rev = git_revert_count(mod, 30)
        sig = mod_signals[mod]
        conf = min(0.95, 0.45 + 0.09 * len(sess_list) + 0.12 * min(3, rev) + 0.05 * min(4, sig))
        kind = "high_touch"
        narrative = (
            f"{mod} appeared in {len(sess_list)} sessions within 14 days "
            f"({sig} sessions mention revert/fail/test/ci in risks or decisions)."
        )
        if rev >= 2 and len(sess_list) >= 3:
            kind = "revert_cycle"
            narrative = (
                f"{mod}: {rev} revert/rollback-related commits in 30d on git; "
                f"{len(sess_list)} recent sessions touch this module. "
                f"Pattern proxy: change → friction (tests/CI) → revert/smaller change."
            )
        anomalies.append(
            {
                "module": mod,
                "kind": kind,
                "narrative": narrative,
                "sessions_in_14d": len(sess_list),
                "git_reverts_30d": rev,
                "signal_sessions": sig,
                "confidence": round(conf, 3),
            }
        )

    anomalies.sort(key=lambda x: -x["confidence"])

    st = load_state()
    seq = int(st.get("next_hypothesis_seq") or 1)
    hypotheses = []
    policies = []

    for a in anomalies[:8]:
        hid = f"H-AUTO-{seq:03d}"
        seq += 1
        if a["kind"] == "revert_cycle":
            hyp = (
                f"implicit dependency or ordering constraint in {a['module']} "
                f"not captured by current types/tests"
            )
            test_rec = (
                "Add integration test that exercises the full HTTP request path "
                "including session creation order and auth boundary."
            )
        else:
            hyp = (
                f"{a['module']} has a high rate of session activity — likely an implicit contract "
                f"under-specified in types and tests"
            )
            test_rec = (
                "Add contract test (or snapshot of public API) plus one integration test "
                "covering the dominant call path before the next refactor."
            )
        pred = (
            "If the hidden dependency exists, the new test should fail on first run "
            "until behaviour is aligned or explicitly fixed."
        )
        hypotheses.append(
            {
                "id": hid,
                "pattern": a["kind"],
                "module": a["module"],
                "hypothesis": hyp,
                "test": test_rec,
                "predicted_outcome": pred,
                "validation": "If test fails then passes after fix → confirm; else reject hypothesis",
                "confidence": a["confidence"],
            }
        )

        if a["confidence"] >= 0.72 and (a["sessions_in_14d"] >= 4 or a["git_reverts_30d"] >= 3):
            pol = (
                f'Modules with >{max(2, a["git_reverts_30d"] - 1)} revert/rollback commits in 30 days '
                f'or ≥4 session touches in 14 days likely have implicit contracts not captured in types. '
                f'Before substantive change: add integration test on full request path; test should fail '
                f'before fix when dependency is real.'
            )
            policies.append(
                {
                    "hypothesis_id": hid,
                    "confidence": round(min(0.95, a["confidence"] + 0.08), 3),
                    "evidence": a["narrative"],
                    "proposed_heuristic_title": "H-NEW (auto-suggested)",
                    "proposed_body": pol,
                    "source": f"auto-generated from session-index + git ({a['sessions_in_14d']} sessions, {a['git_reverts_30d']} git signals)",
                    "action": "Human review required before appending to heuristics/operational.md (use promote-heuristics.sh after YAML capture in learning-log.md)",
                }
            )

    st["next_hypothesis_seq"] = seq
    save_state(st)

    print(f"  sessions indexed (30d window): {len(recent)}")
    if not anomalies:
        print("  no anomalies above threshold (need ≥3 module touches in 14d in session-index)")
    for a in anomalies[:5]:
        print("ANOMALY DETECTED:")
        print(f"  {a['narrative']}")
        print(f"  Hypothesis: module `{a['module']}` may carry implicit contracts under-tested")
        print(f"  Confidence: {a['confidence']:.2f} (sessions={a['sessions_in_14d']}, git_reverts={a['git_reverts_30d']})")
        print("")

    for h in hypotheses[:5]:
        print(f"HYPOTHESIS {h['id']}:")
        print(f"  Pattern: {h['pattern']} on {h['module']}")
        print(f"  Hypothesis: {h['hypothesis']}")
        print(f"  Test: {h['test']}")
        print(f"  Predicted outcome: {h['predicted_outcome']}")
        print(f"  Validation: {h['validation']}")
        print("")

    for p in policies[:3]:
        print(f"POLICY SUGGESTION (confidence: {p['confidence']:.2f}):")
        print(f"  Evidence: {p['evidence']}")
        print(f"  Proposed heuristic: {p['proposed_heuristic_title']}")
        print(f"    {p['proposed_body']}")
        print(f"  Source: {p['source']}")
        print(f"  Action required: {p['action']}")
        print("")

    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(
        json.dumps(
            {
                "generated_at": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
                "anomalies": anomalies,
                "hypotheses": hypotheses,
                "policy_suggestions": policies,
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    print(f"  wrote {REPORT.as_posix()}")


if __name__ == "__main__":
    main()
PY

exit 0
