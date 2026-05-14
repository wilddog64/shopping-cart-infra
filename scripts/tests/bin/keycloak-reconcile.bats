#!/usr/bin/env bats

@test "keycloak-reconcile: --help exits 0" {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  run "$repo_root/bin/keycloak-reconcile.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: keycloak-reconcile.sh"* ]]
}

@test "keycloak-reconcile: make target points at the helper" {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  run make -C "$repo_root" -n keycloak-reconcile
  [ "$status" -eq 0 ]
  [[ "$output" == *"./bin/keycloak-reconcile.sh"* ]]
}

@test "keycloak-reconcile: fails cleanly when no keycloak pod exists" {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  tmpdir="$(mktemp -d)"
  cat >"$tmpdir/kubectl" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "get" && "$2" == "pod" ]]; then
  exit 0
fi
echo "unexpected kubectl call: $*" >&2
exit 1
EOF
  chmod +x "$tmpdir/kubectl"

  PATH="$tmpdir:$PATH" run "$repo_root/bin/keycloak-reconcile.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no Keycloak pod found in namespace identity"* ]]
}
