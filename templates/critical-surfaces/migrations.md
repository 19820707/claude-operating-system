# Critical Surface: migrations

**Model:** Opus mandatory
**Mode:** Critical — explicit approval required before any change
**Fail posture:** additive-first — prefer additive migrations; destructive requires explicit approval

---

## What counts as this surface

- SQL schema migrations (CREATE, ALTER, DROP)
- column additions, removals, type changes, constraints
- index creation or removal
- data backfills or transformations
- ORM model changes that affect schema
- seed data changes in production

---

## Migration classification

| Type | Risk | Approval |
|------|------|---------|
| Additive (ADD COLUMN nullable) | Low | Fast mode |
| Additive (ADD INDEX) | Low-medium | Fast mode |
| Non-additive (DROP COLUMN) | High | Critical mode + explicit |
| Non-additive (ALTER type) | High | Critical mode + explicit |
| NOT NULL without default | High | Critical mode + explicit |
| Data backfill (UPDATE) | High | Critical mode + explicit |
| DROP TABLE | Critical | Explicit + backup confirmation |

---

## Pre-implementation checklist

- [ ] Migration type classified (additive vs non-additive)
- [ ] Rollback migration defined (down migration or manual procedure)
- [ ] Zero-downtime: does migration work while old code is running?
- [ ] Backward compatible: does old code break if new column exists?
- [ ] Data loss assessed: could any row lose data?
- [ ] Index impact: does migration lock the table?
- [ ] IF NOT EXISTS / IF EXISTS used where applicable

---

## Implementation rules

- Additive only by default — never drop without explicit approval
- Always use `IF NOT EXISTS` for ADD COLUMN and CREATE INDEX
- Never add NOT NULL without a default or a backfill migration
- Keep migration files small — one logical change per file
- Name migrations clearly: `<number>_<description>.sql`
- Never edit a migration that has already been applied to any environment

---

## Validation checklist

- [ ] Migration runs cleanly on a fresh schema
- [ ] Migration is idempotent (safe to run twice) where applicable
- [ ] Down migration defined and tested
- [ ] Application code works with both old and new schema (during rollout)
- [ ] `npm run check:migrations` (or equivalent) passes

---

## Rollback

```bash
# Additive migration rollback (drop the added column)
ALTER TABLE <table> DROP COLUMN IF EXISTS <column>;

# Index rollback
DROP INDEX IF EXISTS <index_name>;

# For non-additive: restore from backup or run down migration
# Document exact procedure BEFORE applying the migration
```

---

## Anti-patterns

| Anti-pattern | Risk |
|-------------|------|
| NOT NULL column without default on existing table | All existing rows fail constraint |
| Migration that locks table without downtime plan | Production outage |
| Editing an applied migration | Divergence between environments |
| DROP without backup confirmation | Irreversible data loss |
| Large data backfill in a single transaction | Lock timeout, partial failure |
