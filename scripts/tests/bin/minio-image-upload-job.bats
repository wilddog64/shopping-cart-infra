#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  manifest_path="${MINIO_IMAGE_UPLOAD_MANIFEST:-${repo_root}/data-layer/minio/image-upload-job.yaml}"
  workflow_path="${repo_root}/.github/workflows/minio-uploader-image.yml"
}

@test "M3: image-upload Job has an active deadline of at most 600 seconds" {
  run python3 - "${manifest_path}" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as manifest_file:
    document = yaml.safe_load(manifest_file)

deadline = document["spec"].get("activeDeadlineSeconds")
assert isinstance(deadline, int) and deadline <= 600, deadline
PY
  [ "$status" -eq 0 ]
}

@test "M4: image-upload Job deletes prior hooks and succeeded hooks" {
  run python3 - "${manifest_path}" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as manifest_file:
    document = yaml.safe_load(manifest_file)

policy = document["metadata"]["annotations"].get("argocd.argoproj.io/hook-delete-policy", "")
assert {item.strip() for item in policy.split(",")} >= {"BeforeHookCreation", "HookSucceeded"}, policy
PY
  [ "$status" -eq 0 ]
}

@test "N2: image-upload Job has a deadline so a hung uploader cannot block PostSync indefinitely" {
  run python3 - "${manifest_path}" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as manifest_file:
    document = yaml.safe_load(manifest_file)

deadline = document["spec"].get("activeDeadlineSeconds")
assert isinstance(deadline, int) and deadline <= 600, deadline
PY
  [ "$status" -eq 0 ]
}

@test "MinIO uploader workflow builds only the pinned amd64 tags and signs by digest" {
  run python3 - "${workflow_path}" <<'PY'
import sys

workflow = open(sys.argv[1], encoding="utf-8").read()

assert ":latest" not in workflow
assert "ghcr.io/wilddog64/minio-image-uploader:sha-${{ github.sha }}" in workflow
assert "ghcr.io/wilddog64/minio-image-uploader:1.0.0" in workflow
assert "platforms: linux/amd64" in workflow
assert 'cosign sign --yes --key env://COSIGN_KEY "${IMAGE_REF}@${DIGEST}"' in workflow
assert '[ -n "$COSIGN_KEY" ]' in workflow
PY
  [ "$status" -eq 0 ]
}
