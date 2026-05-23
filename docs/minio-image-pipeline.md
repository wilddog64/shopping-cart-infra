# MinIO Product Image Pipeline

**Date:** 2026-05-23
**Status:** Implemented (Milestone v1 — MinIO + image upload)

## Overview

Product images for the ShopCart frontend are stored in MinIO — an in-cluster,
S3-compatible object store. This eliminates the need for external cloud storage
(ACG sandbox S3 is ephemeral and dies with the sandbox) while keeping the same
S3 API available for future migration to real S3.

```
                 ┌──────────────────────────────────────┐
                 │  shopping-cart-data namespace         │
                 │                                      │
  ArgoCD sync ──▶│  MinIO StatefulSet (port 9000/9001)  │
                 │  ├── PVC: 10Gi (/data)               │
                 │  └── bucket: product-images (public) │
                 │                                      │
  PostSync Job ──▶│  image-upload-job                   │
                 │  └── downloads ~20 Picsum images      │
                 │       uploads to product-images/     │
                 └──────────────────────────────────────┘
                          │ ClusterIP :9000
                          ▼
                 ┌──────────────────────────────────────┐
                 │  shopping-cart-apps namespace         │
                 │                                      │
                 │  frontend (nginx)                    │
                 │  └── location /minio/ → MinIO :9000  │◀── browser
                 │                                      │
  PostSync Job ──▶│  product-catalog-seed (1000 rows)   │
                 │  └── image_url = /minio/product-     │
                 │       images/<subcategory>.jpg        │
                 └──────────────────────────────────────┘
```

## Why MinIO

| Option | Verdict |
|--------|---------|
| ACG sandbox S3 | Ephemeral — bucket deleted on sandbox expiry |
| Personal AWS S3 | External dependency, cost, requires separate auth |
| MinIO in-cluster | ✅ S3-compatible, survives pod restarts (PVC), zero external dep |
| Picsum direct URLs | No persistence, can't simulate real S3 API |

## Components

### 1. MinIO StatefulSet (`data-layer/minio/`)

| File | Purpose |
|------|---------|
| `statefulset.yaml` | MinIO server, PVC 10Gi, sync-wave 1 |
| `service.yaml` | ClusterIP :9000 (API) + :9001 (console); NodePort 30900 |
| `secret.yaml` | ESO ExternalSecret → Vault `secret/data/minio/credentials` |
| `bucket-init-job.yaml` | PostSync Job: creates `product-images` bucket, sets anonymous read |
| `image-upload-job.yaml` | PostSync Job: downloads ~20 Picsum images, uploads to MinIO |

### 2. Image strategy

Images are **generated in-cluster** using Python + Pillow — 800×600 JPEG files with a
category-colored background and a centered white label.

**No external downloads.** Picsum/Unsplash or any third-party image service is intentionally
avoided: automated bulk downloads can violate terms of service, create external network
dependencies, and introduce IP ambiguity. Pillow-generated images are entirely original,
deterministic, and work on air-gapped clusters.

Generation happens once in the `minio-image-upload` PostSync Job. Re-runs skip
already-uploaded images (idempotent `mc stat` check before each upload).

Subcategory → image mapping (20 images total):

| Subcategory slug | Category | Example products |
|-----------------|----------|-----------------|
| `laptop` | Electronics | ProBook, ThinkStation |
| `phone` | Electronics | SmartPhone, Pixel |
| `headphones` | Electronics | ANC Pro, Studio |
| `tablet` | Electronics | PadPro, Tab |
| `speaker` | Electronics | BoomBox, HomePod |
| `keyboard` | Peripherals | Mech TKL, Slim |
| `mouse` | Peripherals | Ergo, Precision |
| `webcam` | Peripherals | HD 1080p, 4K |
| `hub` | Peripherals | USB-C Hub, Dock |
| `monitor-24` | Monitors | 24in FHD |
| `monitor-27` | Monitors | 27in 4K |
| `ultrawide` | Monitors | 34in Ultrawide |
| `curved` | Monitors | 27in Curved |
| `deskpad` | Accessories | XL Deskpad |
| `stand` | Accessories | Monitor Stand |
| `bag` | Accessories | Laptop Bag |
| `charger` | Accessories | 65W GaN |
| `cable` | Accessories | Braided USB-C |
| `light` | Accessories | Key Light |
| `hub-desk` | Accessories | Desktop Hub |

### 3. Image URL format

Images are served through the frontend nginx proxy:

```
/minio/product-images/<subcategory-slug>.jpg
```

The frontend nginx config proxies `location /minio/ → http://minio.shopping-cart-data.svc.cluster.local:9000/`.
This makes image URLs relative and browser-portable — no hardcoded node IP needed.

### 4. Seed job (1,000 products)

A Python-based shell script inside the seed Job generates 1,000 products:
- 4 categories × 5 subcategories × 50 products each
- Name: `{Brand} {Model} {Version}` with rotating lists
- SKU: `{SUBCATEGORY}-{zero-padded-number}` e.g. `LAPTOP-0042`
- Price: randomized within subcategory range (seeded by SKU for stability)
- `image_url`: `/minio/product-images/<subcategory-slug>.jpg`

### 5. Full-text search

A GIN index on a computed `tsvector` column enables fast full-text search:

```sql
CREATE INDEX IF NOT EXISTS products_fts_idx
  ON products
  USING GIN(to_tsvector('english', name || ' ' || COALESCE(description, '') || ' ' || COALESCE(category, '')));
```

The API accepts `GET /api/products?q=<term>` and applies:
```sql
WHERE to_tsvector('english', name || ' ' || COALESCE(description, '') || ' ' || COALESCE(category, ''))
      @@ plainto_tsquery('english', :q)
```

## Bootstrap sequence

On a fresh cluster, ArgoCD applies components in sync-wave order:

```
wave 0: ESO ExternalSecret → creates minio-credentials Secret (from Vault)
wave 1: MinIO StatefulSet starts, PVC provisioned
wave 2: (not used)
PostSync: bucket-init-job → creates product-images bucket (anonymous read)
PostSync: image-upload-job → generates 20 images in-cluster with Pillow, uploads to MinIO
PostSync: product-catalog-seed → inserts 1,000 products with image_url
```

## Prerequisites (manual, once per cluster)

Before ArgoCD sync, the Vault KV secret must exist:

```bash
# Run once after cluster provision (k3d-manager acg-up)
vault kv put secret/minio/credentials \
  root-user=minioadmin \
  root-password="$(openssl rand -base64 24)"
```

This is added to `bin/acg-up` Vault seeding step (see k3d-manager spec).

## Accessing MinIO console

MinIO console is available at `http://<node-ip>:30901` (NodePort 30901).
Credentials come from Vault `secret/data/minio/credentials`.
