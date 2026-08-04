# Image promotion fails against protected service branches

## Symptom

The reusable build workflow successfully builds, scans, and pushes a service
image, but ArgoCD continues running the previous image tag.

## Root cause

The workflow edited `k8s/base/kustomization.yaml` and pushed directly to the
service repository's protected `main` branch. GitHub rejected the push with
`GH006: Changes must be made through a pull request`. The step was marked
`continue-on-error`, so the workflow still appeared successful while the image
promotion was silently skipped.

## Fix

Grant the workflow pull-request write permission, push the manifest update to a
temporary CI branch, and create an auto-merge PR. The workflow now fails on
promotion errors instead of hiding them.

## Verification

Validate the workflow YAML and exercise a service main build. The generated
promotion PR must be created and auto-merged before ArgoCD can observe the new
immutable image tag.
