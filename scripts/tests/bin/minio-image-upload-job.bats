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

@test "M1/N1: MinIO uploader has no runtime package installation command" {
  run python3 - "${manifest_path}" <<'PY'
import re
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as manifest_file:
    document = yaml.safe_load(manifest_file)

uploader = next(container for container in document["spec"]["template"]["spec"]["containers"]
                if container["name"] == "uploader")
command_text = " ".join(str(item) for item in uploader.get("command", []) + uploader.get("args", []))
assert not re.search(r"\b(?:pip|apt|apt-get|install)\b", command_text, re.IGNORECASE), command_text
PY
  [ "$status" -eq 0 ]
}

@test "M2: every image is pinned by tag and digest" {
  run python3 - "${manifest_path}" <<'PY'
import re
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as manifest_file:
    document = yaml.safe_load(manifest_file)

images = []
def collect(value):
    if isinstance(value, dict):
        for key, item in value.items():
            if key == "image":
                images.append(item)
            collect(item)
    elif isinstance(value, list):
        for item in value:
            collect(item)

collect(document)
assert images, "no images found"
for image in images:
    assert re.fullmatch(r"[^@\s:]+(?::[^@\s:]+)@sha256:[0-9a-f]{64}", image), image
PY
  [ "$status" -eq 0 ]
}

@test "N3: MinIO endpoint and bucket remain unchanged" {
  run python3 - "${manifest_path}" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as manifest_file:
    document = yaml.safe_load(manifest_file)

uploader = next(container for container in document["spec"]["template"]["spec"]["containers"]
                if container["name"] == "uploader")
env = {item["name"]: item["value"] for item in uploader["env"]}
assert env["MINIO_BUCKET"] == "product-images", env
assert env["MINIO_ENDPOINT"] == "http://minio.shopping-cart-data.svc.cluster.local:9000", env
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
