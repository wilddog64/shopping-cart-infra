#!/usr/bin/env bats

setup_file() {
  export repo_root="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export test_tmpdir="$(mktemp -d)"
  export venv_dir="${test_tmpdir}/venv"
  python3 -m venv "${venv_dir}"
  "${venv_dir}/bin/pip" install --disable-pip-version-check Pillow==13.0.0
}

teardown_file() {
  rm -rf "${test_tmpdir}"
}

setup() {
  manifest_path="${MINIO_IMAGE_UPLOAD_CONFIGMAP:-${repo_root}/data-layer/minio/image-upload-configmap.yaml}"
  script_path="${test_tmpdir}/generate-and-upload.py"
  python3 - "${manifest_path}" "${script_path}" <<'PY'
import sys
from pathlib import Path

import yaml

manifest = yaml.safe_load(Path(sys.argv[1]).read_text(encoding="utf-8"))
Path(sys.argv[2]).write_text(manifest["data"]["generate-and-upload.py"], encoding="utf-8")
PY
}

make_mc_stub() {
  stub_path="${test_tmpdir}/mc"
  cat >"${stub_path}" <<'SH'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$MC_LOG"
case "${1:-}" in
  alias|stat) exit 0 ;;
  cat)
    if [ -n "${MC_MARKER:-}" ]; then
      printf '%s\n' "$MC_MARKER"
      exit 0
    fi
    exit 1
    ;;
  cp) exit 0 ;;
  *) exit 1 ;;
esac
SH
  chmod +x "${stub_path}"
  printf '%s' "${stub_path}"
}

@test "N1/M1: generated images have no white text outside x 100..700" {
  run env \
    MC_BIN=/bin/true \
    MINIO_ENDPOINT=http://minio.test:9000 \
    MINIO_BUCKET=product-images \
    MINIO_ROOT_USER=root \
    MINIO_ROOT_PASSWORD=secret \
    "${venv_dir}/bin/python" - "${script_path}" <<'PY'
import importlib.util
import sys

from PIL import Image

spec = importlib.util.spec_from_file_location("image_upload", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
for slug, label, bg_color in module.IMAGES:
    path = module.generate_image(slug, label, bg_color)
    image = Image.open(path).convert("RGB")
    for x in list(range(100)) + list(range(701, image.width)):
        for y in range(image.height):
            pixel = image.getpixel((x, y))
            assert not all(channel >= 245 for channel in pixel), (slug, x, y, pixel)
    path.unlink()
PY
  [ "$status" -eq 0 ]
}

@test "N4/N3/N2: art marker controls image refresh and preserves object keys" {
  stub_path="$(make_mc_stub)"
  for marker in missing 1 2; do
    log_path="${test_tmpdir}/mc-${marker}.log"
    if [ "${marker}" != "missing" ]; then
      marker_env=(MC_MARKER="${marker}")
    else
      marker_env=()
    fi
    run env \
      MC_BIN="${stub_path}" \
      MC_LOG="${log_path}" \
      MINIO_ENDPOINT=http://minio.test:9000 \
      MINIO_BUCKET=product-images \
      MINIO_ROOT_USER=root \
      MINIO_ROOT_PASSWORD=secret \
      "${marker_env[@]}" \
      "${venv_dir}/bin/python" "${script_path}"
    [ "$status" -eq 0 ]

    image_cp_count="$(grep -c '^cp /.*\.jpg local/product-images/.*\.jpg$' "${log_path}" || true)"
    marker_cp_count="$(grep -c '^cp /.* local/product-images/\.art-version$' "${log_path}" || true)"
    if [ "${marker}" = "2" ]; then
      [ "${image_cp_count}" -eq 0 ]
      [ "${marker_cp_count}" -eq 0 ]
    else
      [ "${image_cp_count}" -eq 20 ]
      [ "${marker_cp_count}" -eq 1 ]
    fi
    grep -q '^alias set local http://minio.test:9000 root secret$' "${log_path}"
  done
}
