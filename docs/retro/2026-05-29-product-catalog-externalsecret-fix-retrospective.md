# Retrospective — product-catalog-secrets SharedResourceWarning Fix

**Date:** 2026-05-29
**PR:** #78 — merged to main
**Branch:** fix/product-catalog-externalsecret-shared-resource
**Participants:** Claude, Copilot

## What Went Well
- Root cause traced quickly: two ArgoCD Applications claiming same ExternalSecret resource
- Fix was a single file deletion — minimal blast radius
- Confirmed only product-catalog was affected (order/basket/payment have no service-repo ExternalSecret duplicates)
- CI (Validate Manifests) + Copilot review both passed cleanly

## What Went Wrong
- The duplicate ExternalSecret existed for an unknown period before being noticed — likely since the services-git ApplicationSet was introduced
- The data-layer version had 7 keys vs 4 in service-repo version (3 unused aliases); no one caught the discrepancy during the original PR

## Decisions Made
- Sole ownership of `product-catalog-secrets` ExternalSecret goes to the `shopping-cart-product-catalog` Application (services-git ApplicationSet)
- The data-layer `*-apps-externalsecret.yaml` pattern is retained for the 3 other services (order, basket, payment) since they have no service-repo duplicates
- The 3 unused key aliases (`DATABASE_USER`, `DATABASE_PASSWORD`, `RABBITMQ_USER`) are not needed — confirmed by PR #28 pydantic alias investigation

## Theme
A quiet ArgoCD SharedResourceWarning that doesn't block deployments but causes perpetual OutOfSync noise. The fix was architectural cleanup: when a service repo owns its own ExternalSecret, the infra repo should not duplicate it. The data-layer copy was the original source of truth before services-git was introduced; it became a liability once the ApplicationSet took over.
