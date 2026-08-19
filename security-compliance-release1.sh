#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# TEKDI SECURITY COMPLIANCE
# RELEASE 1
#
# Installs:
#   - Gitleaks
#   - detect-secrets
#   - TruffleHog
#   - Ansible
#   - OpenSSH
#   - tmate
#   - Global Git pre-commit hook
#
# Features:
#   - No S3 required
#   - No runtime GitHub download
#   - Uses binaries bundled with npm package
#   - Global Git hook
#   - Scans staged files
#   - Blocks commits containing secrets
#   - Logs installation and scans
# ============================================================

VERSION="release1"

BASE_DIR="$HOME/.security-compliance"
BIN_DIR="$BASE_DIR/bin"
CONFIG_DIR="$BASE_DIR/config"
LOG_DIR="$BASE_DIR/logs"
HOOK_DIR="$HOME/.git-hooks"

TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
INSTALL_LOG="$LOG_DIR/install-$TIMESTAMP.log"

GITLEAKS_VERSION="8.30.0"

# ============================================================
# LOGGING
# ============================================================

mkdir -p "$LOG_DIR"
chmod 700 "$BASE_DIR" 2>/dev/null || true
chmod 700 "$LOG_DIR"

exec > >(tee -a "$INSTALL_LOG") 2>&1

# ============================================================
# COLORS
# ============================================================

RED=""
GREEN=""
YELLOW=""
NC=""

if [[ -t 1 ]]; then
    RED="\033[0;31m"
    GREEN="\033[0;32m"
    YELLOW="\033[1;33m"
    NC="\033[0m"
fi

# ============================================================
# FUNCTIONS
# ============================================================

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

fail() {
    error "$1"
    echo
    echo "Security Compliance Release 1"
    echo "Setup failed."
    echo
    echo "Installation log:"
    echo "$INSTALL_LOG"
    exit 1
}

# ============================================================
# OS DETECTION
# ============================================================

OS="$(uname -s)"
ARCH="$(uname -m)"

echo
echo "=================================================="
echo "   SECURITY COMPLIANCE RELEASE 1"
echo "=================================================="
echo

echo "Operating System : $OS"
echo "Architecture     : $ARCH"
echo "User             : $USER"
echo "Home             : $HOME"
echo "Install directory: $BASE_DIR"
echo
echo "Installation log : $INSTALL_LOG"
echo

# ============================================================
# BASIC REQUIREMENTS
# ============================================================

command -v git >/dev/null 2>&1 || fail "Git is required."

command -v npm >/dev/null 2>&1 || warn "npm was not found."

command -v python3 >/dev/null 2>&1 || fail "Python 3 is required."

command -v pip3 >/dev/null 2>&1 || warn "pip3 was not found."

# ============================================================
# CREATE DIRECTORIES
# ============================================================

mkdir -p "$BASE_DIR"
mkdir -p "$BIN_DIR"
mkdir -p "$CONFIG_DIR"
mkdir -p "$LOG_DIR"
mkdir -p "$HOOK_DIR"

chmod 700 "$BASE_DIR"
chmod 700 "$CONFIG_DIR"
chmod 700 "$LOG_DIR"

# ============================================================
# LOCATE PACKAGE DIRECTORY
#
# The script is executed from:
#
# @tekdi/security-compliance/
#
# Expected:
#
# package/
# ├── bin/
# ├── security-compliance-release1.sh
# └── binaries/
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Package directory:"
echo "$SCRIPT_DIR"
echo

# ============================================================
# GITLEAKS
#
# IMPORTANT:
# DO NOT DOWNLOAD FROM GITHUB.
#
# The npm package must contain the appropriate binary.
# ============================================================

install_gitleaks() {

    echo
    echo "--------------------------------------------------"
    echo "Installing Gitleaks"
    echo "--------------------------------------------------"

    LOCAL_GITLEAKS=""

    case "$OS-$ARCH" in

        Linux-x86_64)
            LOCAL_GITLEAKS="$SCRIPT_DIR/binaries/gitleaks-linux-amd64"
            ;;

        Linux-aarch64)
            LOCAL_GITLEAKS="$SCRIPT_DIR/binaries/gitleaks-linux-arm64"
            ;;

        Linux-arm64)
            LOCAL_GITLEAKS="$SCRIPT_DIR/binaries/gitleaks-linux-arm64"
            ;;

        Darwin-x86_64)
            LOCAL_GITLEAKS="$SCRIPT_DIR/binaries/gitleaks-darwin-amd64"
            ;;

        Darwin-arm64)
            LOCAL_GITLEAKS="$SCRIPT_DIR/binaries/gitleaks-darwin-arm64"
            ;;

        MINGW*|MSYS*|CYGWIN*)
            fail "Windows binary installation must use the Windows package binary."

            ;;

        *)
            fail "Unsupported operating system or architecture: $OS-$ARCH"

            ;;
    esac

    if [[ ! -f "$LOCAL_GITLEAKS" ]]; then
        fail "Bundled Gitleaks binary not found: $LOCAL_GITLEAKS"
    fi

    cp "$LOCAL_GITLEAKS" "$BIN_DIR/gitleaks"

    chmod 700 "$BIN_DIR/gitleaks"

    if ! "$BIN_DIR/gitleaks" version >/dev/null 2>&1; then
        fail "Bundled Gitleaks binary could not be executed."
    fi

    INSTALLED_VERSION="$("$BIN_DIR/gitleaks" version 2>/dev/null || true)"

    echo "Gitleaks version: $INSTALLED_VERSION"

    info "Gitleaks installed."
}

install_gitleaks

# ============================================================
# GITLEAKS CONFIGURATION
# ============================================================

cat > "$CONFIG_DIR/gitleaks.toml" <<'EOF'
title = "Tekdi Security Compliance"

[extend]
useDefault = true
EOF

chmod 600 "$CONFIG_DIR/gitleaks.toml"

info "Gitleaks configuration created."

# ============================================================
# PYTHON VIRTUAL ENVIRONMENT
# ============================================================

VENV_DIR="$BASE_DIR/venv"

if [[ ! -d "$VENV_DIR" ]]; then

    echo
    echo "Creating Python virtual environment..."

    python3 -m venv "$VENV_DIR" || \
        fail "Unable to create Python virtual environment."

fi

PYTHON="$VENV_DIR/bin/python"
PIP="$VENV_DIR/bin/pip"

# ============================================================
# DETECT-SECRETS
# ============================================================

echo
echo "--------------------------------------------------"
echo "Installing detect-secrets"
echo "--------------------------------------------------"

if ! "$VENV_DIR/bin/detect-secrets" --version >/dev/null 2>&1; then

    "$PIP" install --disable-pip-version-check detect-secrets || \
        fail "Failed to install detect-secrets."

fi

info "detect-secrets installed."

# ============================================================
# TRUFFLEHOG
#
# Prefer bundled binary.
# ============================================================

echo
echo "--------------------------------------------------"
echo "Installing TruffleHog"
echo "--------------------------------------------------"

TRUFFLE_DEST="$BIN_DIR/trufflehog"

LOCAL_TRUFFLE=""

case "$OS-$ARCH" in

    Linux-x86_64)
        LOCAL_TRUFFLE="$SCRIPT_DIR/binaries/trufflehog-linux-amd64"
        ;;

    Linux-aarch64)
        LOCAL_TRUFFLE="$SCRIPT_DIR/binaries/trufflehog-linux-arm64"
        ;;

    Linux-arm64)
        LOCAL_TRUFFLE="$SCRIPT_DIR/binaries/trufflehog-linux-arm64"
        ;;

    Darwin-x86_64)
        LOCAL_TRUFFLE="$SCRIPT_DIR/binaries/trufflehog-darwin-amd64"
        ;;

    Darwin-arm64)
        LOCAL_TRUFFLE="$SCRIPT_DIR/binaries/trufflehog-darwin-arm64"
        ;;

    *)
        LOCAL_TRUFFLE=""
        ;;
esac

if [[ -n "$LOCAL_TRUFFLE" && -f "$LOCAL_TRUFFLE" ]]; then

    cp "$LOCAL_TRUFFLE" "$TRUFFLE_DEST"
    chmod 700 "$TRUFFLE_DEST"

else

    warn "Bundled TruffleHog binary not found."

    if command -v trufflehog >/dev/null 2>&1; then
        TRUFFLE_DEST="$(command -v trufflehog)"
    else
        fail "TruffleHog is not available."
    fi

fi

"$TRUFFLE_DEST" --version || true

info "TruffleHog installed."

# ============================================================
# ANSIBLE
# ============================================================

echo
echo "--------------------------------------------------"
echo "Installing Ansible"
echo "--------------------------------------------------"

if command -v ansible >/dev/null 2>&1; then

    info "Ansible already installed."

else

    if command -v apt-get >/dev/null 2>&1; then

        echo "Installing Ansible using apt..."

        sudo apt-get update -y
        sudo apt-get install -y ansible

    elif command -v brew >/dev/null 2>&1; then

        brew install ansible

    else

        warn "Unable to automatically install Ansible on this operating system."

    fi

fi

if command -v ansible >/dev/null 2>&1; then
    ansible --version | head -1
else
    warn "Ansible is not available."
fi

# ============================================================
# OPENSSH
# ============================================================

echo
echo "--------------------------------------------------"
echo "Checking OpenSSH"
echo "--------------------------------------------------"

if command -v ssh >/dev/null 2>&1; then

    ssh -V 2>&1 || true
    info "OpenSSH available."

else

    if command -v apt-get >/dev/null 2>&1; then

        sudo apt-get update -y
        sudo apt-get install -y openssh-client

    elif command -v brew >/dev/null 2>&1; then

        brew install openssh

    else

        warn "OpenSSH could not be installed automatically."

    fi

fi

# ============================================================
# TMATE
# ============================================================

echo
echo "--------------------------------------------------"
echo "Checking tmate"
echo "--------------------------------------------------"

if command -v tmate >/dev/null 2>&1; then

    info "tmate already installed."

else

    if command -v apt-get >/dev/null 2>&1; then

        sudo apt-get update -y
        sudo apt-get install -y tmate || \
            warn "tmate installation failed."

    elif command -v brew >/dev/null 2>&1; then

        brew install tmate || \
            warn "tmate installation failed."

    else

        warn "tmate could not be installed automatically."

    fi

fi

# ============================================================
# GLOBAL GIT HOOK
# ============================================================

echo
echo "--------------------------------------------------"
echo "Installing Global Git Pre-Commit Hook"
echo "--------------------------------------------------"

HOOK_FILE="$HOOK_DIR/pre-commit"

cat > "$HOOK_FILE" <<'HOOK'
#!/usr/bin/env bash

set -Eeuo pipefail

BASE_DIR="$HOME/.security-compliance"
BIN_DIR="$BASE_DIR/bin"
CONFIG_DIR="$BASE_DIR/config"
LOG_DIR="$BASE_DIR/logs"

GITLEAKS="$BIN_DIR/gitleaks"
GITLEAKS_CONFIG="$CONFIG_DIR/gitleaks.toml"

TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
SCAN_LOG="$LOG_DIR/scan-$TIMESTAMP.log"

mkdir -p "$LOG_DIR"

chmod 700 "$LOG_DIR"

exec > >(tee -a "$SCAN_LOG") 2>&1

TMP_DIR="$(mktemp -d)"
SCAN_DIR="$TMP_DIR/staged"

cleanup() {
    rm -rf "$TMP_DIR" >/dev/null 2>&1 || true
}

trap cleanup EXIT

echo
echo "============================================================"
echo "       TEKDI SECURITY COMPLIANCE SECRET SCAN"
echo "============================================================"
echo
echo "Repository : $(git rev-parse --show-toplevel)"
echo "Time       : $(date)"
echo "Scan log   : $SCAN_LOG"
echo

mkdir -p "$SCAN_DIR"

# ============================================================
# GET STAGED FILES
# ============================================================

STAGED_FILES="$(
    git diff \
        --cached \
        --name-only \
        --diff-filter=ACMR
)"

if [[ -z "$STAGED_FILES" ]]; then
    echo "No staged files."
    exit 0
fi

READABLE_FILES=0

while IFS= read -r FILE
do

    [[ -z "$FILE" ]] && continue

    MODE="$(
        git ls-files -s -- "$FILE" 2>/dev/null \
        | awk '{print $1}'
    )"

    # Ignore submodules.
    [[ "$MODE" == "160000" ]] && continue

    if ! git cat-file -e ":$FILE" 2>/dev/null; then
        continue
    fi

    TARGET="$SCAN_DIR/$FILE"

    mkdir -p "$(dirname "$TARGET")"

    if git show ":$FILE" > "$TARGET" 2>/dev/null; then
        READABLE_FILES=$((READABLE_FILES + 1))
    fi

done <<< "$STAGED_FILES"

if [[ "$READABLE_FILES" -eq 0 ]]; then
    echo "No readable staged files."
    exit 0
fi

# ============================================================
# GITLEAKS
# ============================================================

echo
echo "[1/3] Running Gitleaks..."

if [[ ! -x "$GITLEAKS" ]]; then

    echo
    echo "ERROR: Gitleaks is not installed."
    echo "COMMIT BLOCKED."
    echo
    echo "Scan log:"
    echo "$SCAN_LOG"

    exit 1

fi

if ! "$GITLEAKS" dir "$SCAN_DIR" \
    --config "$GITLEAKS_CONFIG" \
    --redact
then

    echo
    echo "============================================================"
    echo "                 GITLEAKS DETECTION"
    echo "============================================================"
    echo
    echo "Potential secret detected."
    echo
    echo "COMMIT BLOCKED."
    echo
    echo "Scan log:"
    echo "$SCAN_LOG"
    echo

    exit 1

fi

echo "[OK] Gitleaks passed."

# ============================================================
# DETECT-SECRETS
# ============================================================

echo
echo "[2/3] Running detect-secrets..."

DETECT="$BASE_DIR/venv/bin/detect-secrets"

if [[ ! -x "$DETECT" ]]; then

    echo "ERROR: detect-secrets is not installed."
    echo "COMMIT BLOCKED."
    echo
    echo "Scan log:"
    echo "$SCAN_LOG"

    exit 1

fi

DETECT_OUTPUT="$TMP_DIR/detect-secrets.json"

if ! "$DETECT" scan "$SCAN_DIR" > "$DETECT_OUTPUT"
then

    echo "ERROR: detect-secrets execution failed."
    echo "COMMIT BLOCKED."

    exit 1

fi

DETECT_COUNT="$(
    python3 - "$DETECT_OUTPUT" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], "r") as f:
        data = json.load(f)

    results = data.get("results", {})

    count = sum(len(v) for v in results.values())

    print(count)

except Exception:
    print(0)
PY
)"

if [[ "$DETECT_COUNT" -gt 0 ]]; then

    echo
    echo "============================================================"
    echo "              DETECT-SECRETS DETECTION"
    echo "============================================================"
    echo
    echo "Potential secret detected."
    echo
    echo "COMMIT BLOCKED."
    echo
    echo "Scan log:"
    echo "$SCAN_LOG"
    echo

    exit 1

fi

echo "[OK] detect-secrets passed."

# ============================================================
# TRUFFLEHOG
# ============================================================

echo
echo "[3/3] Running TruffleHog..."

TRUFFLE="$BASE_DIR/bin/trufflehog"

if [[ ! -x "$TRUFFLE" ]]; then

    TRUFFLE="$(command -v trufflehog || true)"

fi

if [[ -z "$TRUFFLE" || ! -x "$TRUFFLE" ]]; then

    echo "ERROR: TruffleHog is not installed."
    echo "COMMIT BLOCKED."
    echo
    echo "Scan log:"
    echo "$SCAN_LOG"

    exit 1

fi

if ! "$TRUFFLE" filesystem "$SCAN_DIR" \
    --no-update \
    --no-verification
then

    echo
    echo "============================================================"
    echo "              TRUFFLEHOG DETECTION"
    echo "============================================================"
    echo
    echo "Potential secret detected."
    echo
    echo "COMMIT BLOCKED."
    echo
    echo "Scan log:"
    echo "$SCAN_LOG"
    echo

    exit 1

fi

echo "[OK] TruffleHog passed."

# ============================================================
# SUCCESS
# ============================================================

echo
echo "============================================================"
echo "       SECURITY COMPLIANCE CHECK PASSED"
echo "       No secrets detected."
echo "       COMMIT ALLOWED."
echo "============================================================"
echo
echo "Scan log:"
echo "$SCAN_LOG"
echo

exit 0
HOOK

chmod 700 "$HOOK_FILE"

# ============================================================
# CONFIGURE GLOBAL GIT HOOK
# ============================================================

git config --global core.hooksPath "$HOOK_DIR"

info "Global Git hook configured."

echo
echo "Global hook path:"
git config --global --get core.hooksPath

# ============================================================
# VERIFY INSTALLATION
# ============================================================

echo
echo "--------------------------------------------------"
echo "Verifying installation"
echo "--------------------------------------------------"

echo

if [[ -x "$GITLEAKS" ]]; then
    echo "[OK] gitleaks"
    "$GITLEAKS" version || true
else
    echo "[FAIL] gitleaks"
fi

if [[ -x "$VENV_DIR/bin/detect-secrets" ]]; then
    echo "[OK] detect-secrets"
    "$VENV_DIR/bin/detect-secrets" --version || true
else
    echo "[FAIL] detect-secrets"
fi

if [[ -x "$BIN_DIR/trufflehog" ]]; then
    echo "[OK] trufflehog"
    "$BIN_DIR/trufflehog" --version || true
elif command -v trufflehog >/dev/null 2>&1; then
    echo "[OK] trufflehog"
else
    echo "[FAIL] trufflehog"
fi

if command -v ansible >/dev/null 2>&1; then
    echo "[OK] ansible"
else
    echo "[WARN] ansible"
fi

if command -v ssh >/dev/null 2>&1; then
    echo "[OK] openssh"
else
    echo "[WARN] openssh"
fi

if command -v tmate >/dev/null 2>&1; then
    echo "[OK] tmate"
else
    echo "[WARN] tmate"
fi

if [[ -x "$HOOK_FILE" ]]; then
    echo "[OK] global git pre-commit hook"
else
    echo "[FAIL] global git pre-commit hook"
fi

# ============================================================
# FINAL
# ============================================================

echo
echo "=================================================="
echo "   SECURITY COMPLIANCE RELEASE 1"
echo "=================================================="
echo
echo "Security setup completed successfully."
echo
echo "Git security scanning is now enabled globally."
echo
echo "Installed components:"
echo "  - Gitleaks"
echo "  - detect-secrets"
echo "  - TruffleHog"
echo "  - Ansible"
echo "  - OpenSSH"
echo "  - tmate"
echo "  - Global Git pre-commit hook"
echo
echo "Configuration:"
echo "  $CONFIG_DIR/gitleaks.toml"
echo
echo "Logs:"
echo "  $LOG_DIR"
echo
echo "Global Git hook:"
echo "  $HOOK_FILE"
echo
echo "Installation log:"
echo "  $INSTALL_LOG"
echo
echo "Installation completed successfully."
echo

exit 0
