# Issue 003 — CI Stabilization Follow-ups

## Summary

During the March 2026 CI stabilization pass, the required code changes were
committed across all service repositories. Two items could not be validated
locally from the macOS runner due to tooling constraints:

1. `shopping-cart-frontend` `npm run build` still fails because the current
   `vite.config.ts` includes a `test` property that Vite's config typings do not
   recognise. The TS errors that were blocking CI (missing `vite/client` types
   and unused imports) are resolved, but the existing Vite config still needs to
   be updated separately.
2. `shopping-cart-payment`, `rabbitmq-client-java`, and `shopping-cart-order`
   require Maven for local verification. The macOS host lacks `mvn` and the
   Maven wrapper downloads time out (>200s). CI on GitHub will need to confirm
   the workflow updates once the branches are pushed.

## Reproduction

### Frontend
```
npm install
npm run build  # fails with TS2769 in vite.config.ts ("test" property)
```

### Maven-based services
```
# mvn / mvnw unavailable on local macOS host
./mvnw clean package  # hangs while downloading wrapper
```

## Next Steps

- Update `vite.config.ts` in `shopping-cart-frontend` to remove or properly type
  the `test` configuration so `npm run build` succeeds locally.
- Run the Maven workflows on an environment with Maven installed (or rely on
  GitHub Actions CI) to confirm the `-Dmaven.multiModuleProjectDirectory=.` and
  GitHub Packages publishing changes.
