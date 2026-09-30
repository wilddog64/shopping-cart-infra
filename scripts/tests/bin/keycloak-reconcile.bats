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

make_reconcile_probe() {
  local repo_root="$1"
  render_hook_script "${repo_root}"
  printf '#!/usr/bin/env bash\nset -euo pipefail\n' > "${test_tmpdir}/reconcile-probe.sh"
  sed -n '/# BEGIN reconcile support helpers/,/# END reconcile support helpers/p' "${test_tmpdir}/hook.sh" \
    | sed 's/^          //' \
    | sed 's|/opt/keycloak/bin/kcadm.sh|kcadm.sh|g' >> "${test_tmpdir}/reconcile-probe.sh"
  sed -n '/# BEGIN reconcile browser flow/,/# END reconcile browser flow/p' "${test_tmpdir}/hook.sh" \
    | sed 's/^          //' \
    | sed 's|/opt/keycloak/bin/kcadm.sh|kcadm.sh|g' >> "${test_tmpdir}/reconcile-probe.sh"
  printf '\nKC_REALM=shopping-cart\nbrowser_flow=browser-with-conditional-otp\nforms_display_name="${browser_flow} forms"\nconditional_otp_display_name="${browser_flow} Browser - Conditional OTP"\nreconcile_browser_flow\nreconcile_rc=$?\nprintf "reconcile_rc=%%s\\n" "${reconcile_rc}"\n' >> "${test_tmpdir}/reconcile-probe.sh"
  chmod +x "${test_tmpdir}/reconcile-probe.sh"
}

make_reconcile_kcadm_stub() {
  mkdir -p "${test_tmpdir}/bin"
  cat > "${test_tmpdir}/bin/kcadm.sh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
args="$*"
updates_file="${KCADM_UPDATES:?}"

if [[ "${args}" == *"--fields id,displayName,requirement,authenticationFlow,flowId,level"* ]]; then
  cat <<'CSV'
"72f9df5f-9326-41de-9c75-dfc9f64161e9","Cookie","ALTERNATIVE",,,0
"b7a5af7e-2b1d-4e9c-9210-5a964d0f6ee4","Kerberos","DISABLED",,,0
"4132b009-6492-4bf2-8fc9-c23d5c326419","Identity Provider Redirector","ALTERNATIVE",,,0
"837de7dc-c162-4e6e-875a-206856e6a152","browser-with-conditional-otp forms","ALTERNATIVE",true,"1b41e828-6706-41b9-8a3a-50b2013e7e1d",0
"47df1e22-2f22-478f-bddc-32a9871a346f","Username Password Form","REQUIRED",,,1
"f3e14e86-26d4-4a7f-9bbb-0a6ab26514e4","browser-with-conditional-otp Browser - Conditional OTP","CONDITIONAL",true,"f01f2d25-00eb-4840-94d4-92a24cb78d68",1
"c93c67dd-14ae-4d7c-afde-4da9082a4300","Condition - user configured","REQUIRED",,,2
"ac0bb8fe-bc30-4f32-8b95-423f33a9e44a","OTP Form","REQUIRED",,,2
"2ed55ec6-0fe7-4298-a396-a07f8ad33993","Condition - user role","REQUIRED",,,2
CSV
  exit 0
fi

if [[ "${args}" == *"--fields id,displayName,providerId,requirement,authenticationFlow,flowId"* ]]; then
  cat <<'CSV'
"47df1e22-2f22-478f-bddc-32a9871a346f","Username Password Form","auth-username-password-form","REQUIRED",false,
"f3e14e86-26d4-4a7f-9bbb-0a6ab26514e4","browser-with-conditional-otp Browser - Conditional OTP","","CONDITIONAL",true,"f01f2d25-00eb-4840-94d4-92a24cb78d68"
CSV
  exit 0
fi

if [[ "${args}" == *"--fields id,providerId,authenticationConfig"* ]]; then
  printf '"2ed55ec6-0fe7-4298-a396-a07f8ad33993","conditional-user-role","config-role-1"\n'
  exit 0
fi

if [[ "${args}" == *"--fields id,providerId"* ]]; then
  printf '"2ed55ec6-0fe7-4298-a396-a07f8ad33993","conditional-user-role"\n'
  printf '"ac0bb8fe-bc30-4f32-8b95-423f33a9e44a","auth-otp-form"\n'
  exit 0
fi

if [[ "${args}" == update* ]]; then
  printf '%s\n' "${args}" >> "${updates_file}"
  if [[ "${args}" == *'"authenticationFlow":true'* && "${args}" != *'"flowId":'* ]]; then
    echo "Resource not found for url" >&2
    exit 1
  fi
  exit 0
fi

if [[ "${args}" == delete* || "${args}" == create* ]]; then
  exit 0
fi

echo "Unhandled kcadm call: ${args}" >&2
exit 1
STUB
  chmod +x "${test_tmpdir}/bin/kcadm.sh"
  : > "${test_tmpdir}/updates"
  export KCADM_UPDATES="${test_tmpdir}/updates"
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

@test "keycloak-reconcile hook: every sub-flow update includes flowId" {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  render_hook_script "${repo_root}"
  run python3 - "${test_tmpdir}/hook.sh" <<'PY'
import sys

lines = open(sys.argv[1]).read().splitlines()
auth_flow_lines = [index for index, line in enumerate(lines) if r'\"authenticationFlow\":true' in line]
assert len(auth_flow_lines) == 2, auth_flow_lines
for index in auth_flow_lines:
    assert any(r'\"flowId\":\"' in lines[offset] for offset in (index, index + 1)), index
PY
  [ "$status" -eq 0 ]
}

@test "keycloak-reconcile hook: reconciles the captured flow with both IDs" {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  make_reconcile_probe "${repo_root}"
  make_reconcile_kcadm_stub
  run env PATH="${test_tmpdir}/bin:${PATH}" "${test_tmpdir}/reconcile-probe.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"reconcile_rc=0"* ]]
  run cat "${test_tmpdir}/updates"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"flowId":"1b41e828-6706-41b9-8a3a-50b2013e7e1d"'* ]]
  [[ "$output" == *'"flowId":"f01f2d25-00eb-4840-94d4-92a24cb78d68"'* ]]
}
