#!/bin/bash
# Build Claudario.app bundle
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${CONFIG:-release}"
APP_NAME="Claudario"
APP_DIR="build/${APP_NAME}.app"
RESOURCES_DIR="${APP_DIR}/Contents/Resources"
MACOS_DIR="${APP_DIR}/Contents/MacOS"

echo "==> Building Swift package (${CONFIG})"
swift build -c "${CONFIG}"

BIN_PATH=".build/${CONFIG}/${APP_NAME}"
if [[ ! -f "${BIN_PATH}" ]]; then
    echo "Build output not found at ${BIN_PATH}" >&2
    exit 1
fi

echo "==> Assembling .app bundle at ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${BIN_PATH}" "${MACOS_DIR}/${APP_NAME}"
cp Info.plist.template "${APP_DIR}/Contents/Info.plist"

# Bundle the hook script alongside the binary so the app can install it
cp claudario-hook "${RESOURCES_DIR}/claudario-hook"
chmod +x "${RESOURCES_DIR}/claudario-hook"

# Ad-hoc codesign so the app can be launched without Gatekeeper warnings
codesign --force --deep --sign - "${APP_DIR}" 2>/dev/null || true

echo "==> Built ${APP_DIR}"
echo "    Run with: open ${APP_DIR}"
echo "    Or:       ${MACOS_DIR}/${APP_NAME}"
