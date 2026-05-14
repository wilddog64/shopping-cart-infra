#!/usr/bin/env bats

@test "keycloak-reconcile hook: renders a PostSync job with partial import" {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  run kubectl kustomize "$repo_root/identity/keycloak"
  [ "$status" -eq 0 ]
  [[ "$output" == *"argocd.argoproj.io/hook: PostSync"* ]]
  [[ "$output" == *"argocd.argoproj.io/hook-delete-policy: BeforeHookCreation,HookSucceeded"* ]]
  [[ "$output" == *"activeDeadlineSeconds: 900"* ]]
  [[ "$output" == *"kcadm.sh create partialImport"* ]]
  [[ "$output" == *"ifResourceExists=OVERWRITE"* ]]
  [[ "$output" == *"LDAP_BIND_CREDENTIAL"* ]]
  [[ "$output" != *"kc.sh import"* ]]
  [[ "$output" != *"keycloak-reconcile.sh"* ]]
}
