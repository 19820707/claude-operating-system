#!/usr/bin/env bash
# Policy compliance audit over .claude/decision-log.jsonl (verifiable governance). H10: LF-only; exit 0.
set -euo pipefail

echo "[OS-AUDIT]"

if ! command -v python3 >/dev/null 2>&1; then
  echo "  skip: python3 not available"
  exit 0
fi

python3 - "$@" <<'PY'
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

LOG = Path(".claude/decision-log.jsonl")
OUT = Path(".claude/policy-audit-report.json")

OPUS_REQUIRED = re.compile(
    r"auth|/auth/|session|cookie|csrf|billing|stripe|payment|migration|password|jwt|rbac|oidc|entitlement",
    re.I,
)
MIGRATION = re.compile(r"migration|schema|drizzle|ALTER\s+TABLE", re.I)


def requires_opus(trigger: str) -> bool:
    if not trigger:
        return False
    if MIGRATION.search(trigger):
        return True
    return bool(OPUS_REQUIRED.search(trigger))


def norm_model(d: str) -> str:
    s = (d or "").lower()
    if "opus" in s:
        return "Opus"
    if "sonnet" in s:
        return "Sonnet"
    if "haiku" in s:
        return "Haiku"
    return d or "unknown"


def main():
    filt = None
    args = sys.argv[1:]
    if "--session" in args:
        i = args.index("--session")
        filt = args[i + 1] if i + 1 < len(args) else None

    if not LOG.is_file():
        print("  skip: no decision-log.jsonl (use decision-append.sh before acting)")
        return

    rows = []
    for line in LOG.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            continue

    if filt:
        rows = [r for r in rows if str(r.get("session", "")) == filt]

    checked = 0
    compliant = 0
    violations = []
    lines_out = []

    for r in rows:
        sid = r.get("id", "?")
        sess = r.get("session", "")
        if filt and sess != filt:
            continue
        t = r.get("type", "")
        if t == "model_selection":
            checked += 1
            trig = str(r.get("trigger", ""))
            dec = norm_model(str(r.get("decision", "")))
            need = requires_opus(trig)
            ok = (need and dec == "Opus") or (not need)
            tag = "COMPLIANT" if ok else "NON-COMPLIANT"
            if ok:
                compliant += 1
            else:
                violations.append(
                    {
                        "id": sid,
                        "reason": f"trigger implies Opus but decision={dec}",
                        "trigger": trig[:200],
                    }
                )
            pol = str(r.get("policy_applied", ""))[:60]
            short = trig[:72] + ("…" if len(trig) > 72 else "")
            lines_out.append(
                f"  {sid} model={dec} for {short!r} : {tag} (policy_applied: {pol})"
            )
        elif t == "scope_boundary":
            checked += 1
            exp = r.get("scope_expansion_requested") is True
            dec = str(r.get("decision", "")).lower()
            ok = (not exp) or (
                "author" in dec
                or "approval" in dec
                or "human" in dec
                or "denied" in dec
                or "not approved" in dec
                or "out of scope" in dec
                or "out-of-scope" in dec
            )
            tag = "COMPLIANT" if ok else "NON-COMPLIANT"
            if ok:
                compliant += 1
            else:
                violations.append({"id": sid, "reason": "scope expansion without explicit authorisation path"})
            lines_out.append(f"  {sid} scope_boundary : {tag}")

    if filt:
        print(f"  session filter: {filt}")
    for ln in lines_out[-40:]:
        print(ln)

    rate = (compliant / checked) if checked else 1.0
    print(f"  compliance rate: {rate*100:.1f}% ({compliant}/{checked} audited rows)")
    if violations:
        print(f"  violations: {len(violations)} — review before next session")
        for v in violations[:8]:
            print(f"    - {v['id']}: {v.get('reason')}")
    if checked >= 10 and rate < 0.85:
        print(
            "  DRIFT WARNING: compliance < 85% — policies may be ignored, misunderstood, or overly strict; schedule policy review (not more silent discipline)."
        )

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(
        json.dumps(
            {
                "audited_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                "session_filter": filt,
                "rows_audited": checked,
                "compliant": compliant,
                "compliance_rate": round(rate, 4),
                "violations": violations,
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    print(f"  wrote {OUT.as_posix()}")


if __name__ == "__main__":
    main()
PY

exit 0
