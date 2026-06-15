#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFO_JSON="${REPO_ROOT}/info.json"

if [[ ! -f "${INFO_JSON}" ]]; then
  echo "info.json not found at ${INFO_JSON}" >&2
  exit 1
fi

read -r MOD_NAME VERSION < <(python - <<'PY' "${INFO_JSON}"
import json
import pathlib
import re
import sys

info_path = pathlib.Path(sys.argv[1])
with info_path.open("r", encoding="utf-8") as fh:
    data = json.load(fh)

name = data["name"]
version = data["version"]
if not re.fullmatch(r"(\d+)\.(\d+)\.(\d+)", version):
    raise SystemExit(f"Unsupported version format in info.json: {version}")

print(name, version)
PY
)

PACKAGE_DIR_NAME="${MOD_NAME}_${VERSION}"
ZIP_NAME="${PACKAGE_DIR_NAME}.zip"
TMP_DIR="$(mktemp -d /tmp/${MOD_NAME}.XXXXXX)"
PACKAGE_DIR="${TMP_DIR}/${PACKAGE_DIR_NAME}"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

mkdir -p "${PACKAGE_DIR}"

rsync -a \
  --exclude '.git/' \
  --exclude '.github/' \
  --exclude '.gitignore' \
  --exclude 'scripts/' \
  --exclude 'build/' \
  --exclude '*.zip' \
  --exclude "${PACKAGE_DIR_NAME}/" \
  "${REPO_ROOT}/" "${PACKAGE_DIR}/"

(
  cd "${TMP_DIR}"
  zip -r "${REPO_ROOT}/${ZIP_NAME}" "${PACKAGE_DIR_NAME}" >/dev/null
)

echo "Using info.json version ${VERSION}"
echo "Created ${ZIP_NAME}"
