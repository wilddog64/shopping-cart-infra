# Active Context: shopping-cart-infra

## Current State

Infrastructure stages 1–3 complete. The data layer (PostgreSQL, Redis, RabbitMQ) and identity stack (Keycloak + OpenLDAP) are deployed and functional. Argo CD GitOps is active. Stage 4 (monitoring integration) is in progress via the `observability-stack` sister repository.

## Implementation Progress

### Data Layer
- ✅ Stage 1: RabbitMQ StatefulSet deployed to `shopping-cart-data`
- ✅ Stage 2: Vault integration for RabbitMQ dynamic credentials (via ESO)
- ✅ PostgreSQL StatefulSets: products + orders
- ✅ Redis StatefulSets: cart + orders-cache
- ✅ Vault database secrets engine configured (products + orders roles)
- ✅ ExternalSecrets for all components

### Application Layer
- ✅ Helm chart for all 4 application services
- ✅ Argo CD AppProject + Applications (dev + prod)
- ✅ CI/CD pipeline: GitHub Actions → Jenkins → infra repo → Argo CD

### Identity
- ✅ Keycloak + OpenLDAP deployed in `identity` namespace
- ✅ Realm `shopping-cart` configured with `frontend` client

### Observability
- ⏳ Being handled by `observability-stack` repo (Stage 4)
- RabbitMQ Prometheus plugin enabled (port 15692 available for scraping)

## Known Issues / Docs

- `docs/issues/001-rabbitmq-nodeport.md` — RabbitMQ NodePort access issue
- `docs/issues/002-rabbitmq-prometheus-plugin.md` — Prometheus plugin configuration
- `docs/issues/deployment-troubleshooting.md` — Common deployment issues
- `docs/vault-password-rotation.md` — Rotation testing guide
- `docs/redis-password-rotation.md` — Redis password rotation

## Active Message Schemas

Documented in `docs/message-schemas.md`. Queues/exchanges:
- `cart.checkout` — Basket → Order (checkout event)
- `order.created` → Payment service
- `order.paid` → fulfillment/email

## CI/CD Flow (Current)

```
Application repo push
  → GitHub Actions builds + pushes GHCR image
  → Webhook triggers Jenkins
  → Jenkins updates chart/values-dev.yaml image tag
  → Git push to this repo
  → Argo CD auto-syncs shopping-cart-dev app
```

Docs: `docs/cicd-architecture.md`, `docs/container-image-workflow.md`, `docs/github-actions-webhook-setup.md`

### CI Stabilization (2026-03)
- ✅ `shopping-cart-frontend` — TypeScript import cleanup + `tsconfig` types (`5b69bd0`)
- ✅ `shopping-cart-product-catalog` — Dockerfile security upgrades (`c745bd3`)
- ✅ `shopping-cart-payment` — GitHub Actions `./mvnw` invocations add `-Dmaven.multiModuleProjectDirectory=.` (`7642f06`, local wrapper download timed out; CI verification deferred to GitHub)
- ✅ `rabbitmq-client-java` — GitHub Packages publish job, `distributionManagement`, Maven settings (`0f1c9b1`)
- ✅ `shopping-cart-order` — GitHub Packages repository + workflow uses settings (`75c07bb`, local Maven unavailable)
- ⚠️ Follow-ups tracked in `docs/issues/003-ci-stabilization-followups.md`

## Re-Architecture Plan (2026-02-27)

### Two-Cluster Split

Current single-cluster deployment will be split into two clusters running on the same machine (or two laptops on the same WiFi):

```
infra cluster (OrbStack)          app cluster (k3s / Parallels Ubuntu)
├── secrets/                      ├── shopping-cart/
│   └── Vault + ESO               │   └── basket, order, payment, catalog
├── identity/                     ├── data/
│   └── LDAP + Keycloak           │   └── PostgreSQL, Redis, RabbitMQ
├── cicd/                         └── observability/
│   └── Jenkins + Argo CD             └── app-side metrics + logging
├── observability/
│   └── Prometheus + Grafana + Loki
└── istio-system/
```

**Key decisions:**
- Cluster name carries the `infra` context — no `infra-` prefix needed on namespaces
- `istio-system` stays as-is — Istio hardcodes this namespace
- `observability/` exists in both clusters — infra observes infra, app observes apps
  (alternative: centralise on infra and ship app metrics there — TBD)
- Laptops on same WiFi — use `.local` mDNS hostnames, no VPN needed
  (`m4-air.local` for infra, Parallels VM IP for app cluster)

### Authentication Re-Architecture

Shopping cart apps currently have no centralised auth. Target state:
- Keycloak (`identity/`) is the OIDC broker — apps never touch LDAP directly
- LDAP is Keycloak's user store only
- Frontend redirects to Keycloak for login, gets JWT
- Backend services validate Bearer tokens against Keycloak JWKS endpoint
- Keycloak client secrets live in Vault, ESO syncs them to app cluster

### CI/CD with Two Clusters

```
Developer pushes code
    ↓
GitHub Actions (CI) — builds image, runs tests, pushes to registry,
                      updates image tag in git manifests
    ↓
Argo CD (CD) on infra cluster — detects manifest change,
                                syncs to app cluster
```

Alternatively: Jenkins on infra cluster handles CI, Argo CD handles CD.
Both Jenkins and Argo CD already scaffolded in `cicd/`.

### ESO Cross-Cluster

ESO lives on **app cluster** — pulls secrets from Vault on **infra cluster**:
- App cluster ESO authenticates to Vault via Kubernetes auth
- Vault addr: `https://<infra-cluster-ip>:8200`
- App services get DB credentials, Keycloak client secrets via k8s secrets

---

## Pending Work

- [ ] Stage 4: Wire observability (ServiceMonitors, dashboards) — in `observability-stack` repo
- [ ] RabbitMQ load testing results integration — `docs/rabbitmq-load-testing.md` exists
- [ ] Production promotion workflow documentation
- [ ] Network policies for namespace isolation enforcement
- [ ] **Namespace redesign** — migrate from tool-centric to function-centric namespaces (secrets, identity, cicd, observability)
- [ ] **Two-cluster split** — infra on OrbStack, app on k3s/Parallels
- [ ] **Auth re-architecture** — centralise auth through Keycloak OIDC, back-services validate JWT
- [ ] **ESO cross-cluster** — ESO on app cluster pulling from Vault on infra cluster
