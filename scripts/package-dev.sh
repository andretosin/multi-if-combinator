#!/usr/bin/env bash
# package-dev.sh
# Stages the mod folder under build/ (and a local .zip) for testing, using the
# version in info.json. CI uploads the build/ directory so the artifact keeps
# the mod folder inside it instead of double-zipping.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFO_JSON="${REPO_ROOT}/info.json"

if [[ ! -f "${INFO_JSON}" ]]; then
  echo "info.json not found at ${INFO_JSON}" >&2
  exit 1
fi

read -r MOD_NAME CURRENT_VERSION < <(python - <<'PY' "${INFO_JSON}"
import json
import pathlib
import sys

info_path = pathlib.Path(sys.argv[1])
with info_path.open("r", encoding="utf-8") as fh:
    data = json.load(fh)

print(data["name"], data["version"])
PY
)

PACKAGE_DIR_NAME="${MOD_NAME}_${CURRENT_VERSION}"
ZIP_NAME="${PACKAGE_DIR_NAME}.zip"
BUILD_DIR="${REPO_ROOT}/build"
PACKAGE_DIR="${BUILD_DIR}/${PACKAGE_DIR_NAME}"

# Fresh staging dir that contains only the mod folder, so CI can upload build/
# (the parent) and keep "${PACKAGE_DIR_NAME}/" inside the artifact.
rm -rf "${BUILD_DIR}"
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

# Local convenience zip (one zip -> mod folder -> files) at the repo root.
rm -f "${REPO_ROOT}/${ZIP_NAME}"
(
  cd "${BUILD_DIR}"
  zip -r "${REPO_ROOT}/${ZIP_NAME}" "${PACKAGE_DIR_NAME}" >/dev/null
)

echo "Staged ${PACKAGE_DIR}"
echo "Created ${ZIP_NAME} (version ${CURRENT_VERSION} from info.json)"
