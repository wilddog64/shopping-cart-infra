# Keycloak realm import should skip an existing `shopping-cart` realm

## What happened
The live Keycloak pod starts successfully, but the initContainer import re-runs against a database that already contains the `shopping-cart` realm.

## Actual output
```text
Detail: Key (name)=(shopping-cart) already exists.
2026-05-14 02:02:10,945 ERROR [org.keycloak.services.resources.admin.RealmsAdminResource] (executor-thread-1) Conflict detected: org.keycloak.models.ModelDuplicateException: org.postgresql.util.PSQLException: ERROR: duplicate key value violates unique constraint "uk_orvsdmla56612eaefiq6wl5oi"
  Detail: Key (name)=(shopping-cart) already exists.
```

## Root cause
The Keycloak startup import path currently calls `kc.sh import` on every pod start. When the realm already exists in PostgreSQL, Keycloak tries to create it again and hits the unique constraint on `realm.name`.

## Fix
- Add a startup preflight that checks the Keycloak PostgreSQL database for an existing `shopping-cart` realm.
- Skip the import when the realm already exists.
- Keep client reconciliation and other follow-up config updates separate from first-boot realm seeding.

## Follow-up
- Rebuild the identity stack after this branch merges.
- Verify the live Keycloak logs no longer show the duplicate realm insert or unique-constraint failure.
