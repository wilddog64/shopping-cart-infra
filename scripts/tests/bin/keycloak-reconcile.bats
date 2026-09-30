#!/usr/bin/env bats

setup() {
  test_tmpdir="$(mktemp -d)"
}

teardown() {
  rm -rf "${test_tmpdir}"
}

render_hook_script() {
  local repo_root="$1"
  run kubectl kustomize "${repo_root}/identity/keycloak"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c '
import sys
import yaml

for document in yaml.safe_load_all(sys.stdin.read()):
    if document and document.get("kind") == "Job" and document.get("metadata", {}).get("name") == "keycloak-realm-reconcile":
        print(document["spec"]["template"]["spec"]["containers"][0]["command"][-1], end="")
        break
else:
    raise SystemExit("keycloak-realm-reconcile Job not found")
' > "${test_tmpdir}/hook.sh"
}

make_flow_probe() {
  local repo_root="$1"
  render_hook_script "${repo_root}"
  printf '#!/usr/bin/env bash\nset -euo pipefail\n' > "${test_tmpdir}/probe.sh"
  sed -n '/# BEGIN flow readiness wait/,/# END flow readiness wait/p' "${test_tmpdir}/hook.sh" \
    | sed 's/^          //' \
    | sed 's|/opt/keycloak/bin/kcadm.sh|kcadm.sh|g' >> "${test_tmpdir}/probe.sh"
  printf '\nKC_REALM=shopping-cart\nbrowser_flow=browser-with-conditional-otp\nreconcile_browser_flow() { echo reconciled; }\n' >> "${test_tmpdir}/probe.sh"
  sed -n '/# BEGIN flow readiness dispatch/,/# END flow readiness dispatch/p' "${test_tmpdir}/hook.sh" \
    | sed 's/^          //' \
    | sed 's|/opt/keycloak/bin/kcadm.sh|kcadm.sh|g' >> "${test_tmpdir}/probe.sh"
  printf '\nreconcile_browser_flow\n' >> "${test_tmpdir}/probe.sh"
  chmod +x "${test_tmpdir}/probe.sh"
}

make_kcadm_stub() {
  local mode="$1"
  mkdir -p "${test_tmpdir}/bin"
  cat > "${test_tmpdir}/bin/kcadm.sh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
state_file="${KCADM_STATE:?}"
if [[ "$*" == *"authentication/flows/browser-with-conditional-otp/executions"* ]]; then
  attempts="$(cat "${state_file}")"
  attempts=$((attempts + 1))
  printf '%s\n' "${attempts}" > "${state_file}"
  if [[ "${KCADM_MODE}" == "eventual" && "${attempts}" -ge 4 ]]; then
    exit 0
  fi
  exit 1
fi
if [[ "$*" == *"authentication/flows"* ]]; then
  printf '"browser-with-conditional-otp"\n'
  exit 0
fi
exit 0
STUB
  chmod +x "${test_tmpdir}/bin/kcadm.sh"
  printf '0\n' > "${test_tmpdir}/attempts"
  export KCADM_MODE="${mode}"
  export KCADM_STATE="${test_tmpdir}/attempts"
}

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
  [ "$(grep -c '^[[:space:]]*wait_for_flow_executions$' <<< "$output")" -eq 2 ]
}

@test "keycloak-reconcile hook: waits through three flow execution 404s" {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  make_flow_probe "${repo_root}"
  make_kcadm_stub eventual
  run env PATH="${test_tmpdir}/bin:${PATH}" KEYCLOAK_FLOW_READY_TIMEOUT_SECONDS=60 "${test_tmpdir}/probe.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"browser flow readable after 4 attempt(s)"* ]]
  [ "$(cat "${test_tmpdir}/attempts")" -eq 4 ]
}

@test "keycloak-reconcile hook: gives up when flow executions stay unavailable" {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  make_flow_probe "${repo_root}"
  make_kcadm_stub always
  run timeout 12 env PATH="${test_tmpdir}/bin:${PATH}" KEYCLOAK_FLOW_READY_TIMEOUT_SECONDS=6 "${test_tmpdir}/probe.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: browser flow executions still 404 after "* ]]
  [ "$(cat "${test_tmpdir}/attempts")" -ge 4 ]
}
