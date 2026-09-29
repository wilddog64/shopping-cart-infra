#!/usr/bin/env bats

@test "identity Application: does not enable global resource replacement" {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

  run grep -F -- "- Replace=true" "$repo_root/argocd/applications/identity.yaml"
  [ "$status" -eq 1 ]
}

@test "identity Application: pins normal apply behavior explicitly" {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

  run grep -F -- "- Replace=false" "$repo_root/argocd/applications/identity.yaml"
  [ "$status" -eq 0 ]
}

@test "identity PVC: keeps the resource-level replacement exemption" {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

  run grep -F -- "argocd.argoproj.io/sync-options: Replace=false" \
    "$repo_root/identity/keycloak/postgres.yaml"
  [ "$status" -eq 0 ]
}
