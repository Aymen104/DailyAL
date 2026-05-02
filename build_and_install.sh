#!/usr/bin/env bash
# ============================================================
# DailyAL — Build and Install Script
# Usage:
#   ./build_and_install.sh                       # release APK build + install
#   ./build_and_install.sh debug                 # debug APK build + install
#   ./build_and_install.sh build-only            # build only (no install)
#   ./build_and_install.sh bundle-only           # release app bundle only
#   ./build_and_install.sh first                 # Install on only the first device
#   ./build_and_install.sh --uninstall-first     # Uninstall existing app before install
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Colors ───────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── Defaults ─────────────────────────────────────────────────
VARIANT="release"
BUILD_ONLY=false
UNINSTALL_FIRST=false
ONLY_FIRST=false
ARTIFACT_KIND="apk"

while [[ $# -gt 0 ]]; do
    case "$1" in
        debug|release)
            VARIANT="$1"
            ;;
        first)
            ONLY_FIRST=true
            ;;
        build-only)
            BUILD_ONLY=true
            VARIANT="release"
            ;;
        bundle-only)
            BUILD_ONLY=true
            VARIANT="release"
            ARTIFACT_KIND="bundle"
            ;;
        --uninstall-first)
            UNINSTALL_FIRST=true
            ;;
        *)
            error "Unknown argument '$1'. Use: [debug|release|build-only|bundle-only|first] [--uninstall-first]"
            ;;
    esac
    shift
done

# ── Validate variant ─────────────────────────────────────────
if [[ "$VARIANT" != "debug" && "$VARIANT" != "release" ]]; then
    error "Unknown variant '$VARIANT'. Use: debug | release | build-only | bundle-only"
fi

APP_NAME="DailyAL"
PACKAGE="io.github.jica98"
ACTIVITY=".MainActivity"

if [[ "$ARTIFACT_KIND" == "bundle" ]]; then
    FLUTTER_CMD="flutter build appbundle"
    ARTIFACT_DIR="build/app/outputs/bundle/${VARIANT}"
    ARTIFACT_EXT="aab"
else
    FLUTTER_CMD="flutter build apk"
    if [[ "$VARIANT" == "debug" ]]; then
        ARTIFACT_DIR="build/app/outputs/apk/debug"
    else
        ARTIFACT_DIR="build/app/outputs/apk/${VARIANT}"
    fi
    ARTIFACT_EXT="apk"
fi

# ── Step 1: Build ────────────────────────────────────────────
info "Building ${APP_NAME} ${ARTIFACT_EXT^^} variant: ${VARIANT^}"

if [[ "$VARIANT" == "debug" && "$ARTIFACT_KIND" == "apk" ]]; then
    flutter build apk --debug
elif [[ "$ARTIFACT_KIND" == "bundle" ]]; then
    flutter build appbundle
else
    flutter build apk --release
fi

# Locate artifact
ARTIFACT_PATH=$(find "$ARTIFACT_DIR" -maxdepth 1 -type f -name "*.${ARTIFACT_EXT}" ! -name "*-unsigned.*" 2>/dev/null | sort | head -1)

if [[ -z "$ARTIFACT_PATH" ]]; then
    ARTIFACT_PATH=$(find "$ARTIFACT_DIR" -maxdepth 1 -type f -name "*.${ARTIFACT_EXT}" 2>/dev/null | sort | head -1)
fi

if [[ -z "$ARTIFACT_PATH" ]]; then
    # Fallback: search the entire build output tree
    ARTIFACT_PATH=$(find build/app/outputs -type f -name "*.${ARTIFACT_EXT}" 2>/dev/null | sort | head -1)
fi

if [[ -z "$ARTIFACT_PATH" ]]; then
    error "${ARTIFACT_EXT^^} not found in build/app/outputs"
fi

success "Build complete → ${ARTIFACT_PATH}"

# ── Step 2: Install (optional) ───────────────────────────────
if $BUILD_ONLY; then
    info "Skipping install (build-only mode)"
    exit 0
fi

# Check adb is available
if ! command -v adb &>/dev/null; then
    warn "adb not found in PATH — skipping install"
    warn "Install Android Platform Tools and add to PATH to enable auto-install"
    exit 0
fi

# Check device connected
DEVICE_LIST=$(adb devices | awk 'NR > 1 && $2 == "device" { print $1 }')
if [[ -z "$DEVICE_LIST" ]]; then
    warn "No Android device connected — skipping install"
    warn "Connect a device and enable USB debugging, then re-run this script"
    exit 0
fi

DEVICE_COUNT=$(echo "$DEVICE_LIST" | wc -w)
if [[ "$DEVICE_COUNT" -gt 1 ]]; then
    if $ONLY_FIRST; then
        FIRST_DEVICE=$(echo "$DEVICE_LIST" | awk '{print $1}')
        info "Multiple devices connected ($DEVICE_COUNT) — only installing on the first one ($FIRST_DEVICE)"
    else
        warn "Multiple devices connected ($DEVICE_COUNT) — installing on all of them"
    fi
fi

install_apk() {
    local device="$1"
    local artifact_path="$2"
    local output=""

    if $UNINSTALL_FIRST; then
        warn "Uninstall-first enabled on ${device}; existing app data will be removed"
        adb -s "$device" uninstall "$PACKAGE" >/dev/null 2>&1 || true
    fi

    if output=$(adb -s "$device" install -r "$artifact_path" 2>&1); then
        printf '%s\n' "$output"
        return 0
    fi

    printf '%s\n' "$output"
    if [[ "$output" == *"INSTALL_FAILED_UPDATE_INCOMPATIBLE"* ]]; then
        warn "Existing ${PACKAGE} on ${device} is signed with a different key"
        warn "Re-run with --uninstall-first or run: adb -s ${device} uninstall $PACKAGE"
    fi
    return 1
}

for DEVICE in $DEVICE_LIST; do
    info "Installing on device: $DEVICE…"
    install_apk "$DEVICE" "$ARTIFACT_PATH"

    info "Launching ${PACKAGE}${ACTIVITY} on $DEVICE…"
    adb -s "$DEVICE" shell am start -n "${PACKAGE}/${PACKAGE}${ACTIVITY}" && success "App launched on $DEVICE!"

    if $ONLY_FIRST; then
        info "Stopping after first device as requested."
        break
    fi
done

if $ONLY_FIRST; then
    success "${APP_NAME} (${VARIANT}) processing complete for the first device!"
else
    success "${APP_NAME} (${VARIANT}) processing complete for all devices!"
fi
