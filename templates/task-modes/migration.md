---
name: migration
description: Structured workflow for schema migrations — additive vs destructive, rollback planning, zero-downtime sequencing
type: task-mode
---

# Task Mode: migration

**Model:** Opus — always (schema changes are irreversible without explicit down migration)
**Mode:** Critical — mandatory. No exceptions.
**Approval:** Required before writing any migration file. Required again before running.

---

## When to use

- Adding columns, tables, indexes, constraints
- Removing or renaming columns, tables
- Changing column types or nullability
- Backfilling data
- Any change to the database schema

Not for: application code changes with no schema impact, seed data for development only.

---

## Classification

Before writing anything, classify the migration:

| Type | Examples | Risk |
|------|----------|------|
| Additive | Add nullable column, add index, add table | Low — old code still works |
| Backfill | Populate new column from existing data | Medium — locks, volume, time |
| Constraint tightening | NOT NULL, unique constraint, FK | High — requires backfill first |
| Destructive | Drop column, drop table, rename | Critical — irreversible without restore |
| Type change | varchar→int, expand/shrink length | High — data loss risk |

---

## Sequence

### 1. Classify
- What type is this migration? (see table above)
- Is the column/table referenced in application code today?
- Is there existing data that would violate new constraints?
- What is the estimated row count? (affects lock duration)

### 2. Read current schema
```bash
# Read the latest migration file
# Read the Prisma schema (or equivalent ORM schema)
# Read any existing seed/fixture data that touches this table
```

### 3. Plan the safe sequence
For constraint tightening or destructive changes, use the expand/contract pattern:

**Expand (deploy 1):**
- Add new column as nullable
- Add new table without enforcing relationships
- Keep old column — do not drop yet

**Migrate (deploy 2 or background job):**
- Backfill new column from old
- Validate: count rows where new IS NULL → should be 0
- Only then tighten constraint

**Contract (deploy 3):**
- Remove old column
- Remove old code paths
- Mark old column as deprecated first if traffic is still reading it

### 4. Write the migration

Structure requirements:
- **Up migration**: explicit, idempotent where possible
- **Down migration**: required. If reversal is impossible, state that explicitly and get approval.
- **Estimated duration**: based on row count and operation type
- **Lock risk**: does this acquire table-level lock? (ALTER TABLE, DROP COLUMN)

```sql
-- Example: safe additive migration
ALTER TABLE events ADD COLUMN published_at TIMESTAMPTZ;

-- Example: down
ALTER TABLE events DROP COLUMN IF EXISTS published_at;
```

### 5. Assess application compatibility
- Does existing code break if this column exists? (usually: no)
- Does existing code break if this column is absent? (check: is it SELECT *?)
- Is there a deploy window where old code + new schema coexist?
- Is there a deploy window where new code + old schema coexist?

Both windows must be safe — the migration and the code deploy are not atomic.

### 6. Validate before running
```bash
npm run typecheck          # ORM types re-generated?
npx prisma validate        # schema valid?
# Review migration SQL — read the generated file, not just the schema diff
```

### 7. Run in staging first
- Apply migration to staging
- Run application smoke tests
- Confirm: row counts unchanged, no unexpected NULLs, no broken queries

### 8. Rollback path
State the exact rollback command before running in production:
```bash
# Rollback example (Prisma)
npx prisma migrate resolve --rolled-back <migration-name>
# + run down migration SQL manually if needed
```

---

## Rules

- Never `DROP` before confirming no application code reads the column
- Never add `NOT NULL` without a default or prior backfill
- Never run destructive migration without explicit human approval
- Never assume `migrate deploy` in production is reversible — it may not be
- Down migration is mandatory. If truly impossible, document why and get approval.
- Staging run is mandatory before production

## Anti-patterns

| Anti-pattern | Risk |
|-------------|------|
| NOT NULL column without DEFAULT | Migration fails on existing rows |
| DROP COLUMN without deploy window planning | Old code reads missing column → runtime error |
| No down migration | Cannot rollback if production deploy fails |
| Migration + application change in one PR | Cannot isolate which caused a regression |
| Large backfill without row count estimate | Table lock, timeout, replication lag |
| Running migration before application deploy | New code references column that doesn't exist yet |
| Running migration after application deploy (if code requires new schema) | Runtime error during deploy window |
