#!/usr/bin/env bash

# ============================================================
# TEKDI SECURITY COMPLIANCE INSTALLER
#
# Installs:
#   - Gitleaks
#   - detect-secrets
#   - TruffleHog
#   - Ansible
#   - pre-commit
#   - OpenSSH client
#   - tmate
#
# Configures:
#   - Global Git security hook
#   - Gitleaks configuration
#   - False-positive allowlist support
#   - Persistent installation logs
#
# Security:
#   - No source code is uploaded
#   - No scan results are uploaded
#   - Temporary scan files are deleted
#   - Gitleaks configuration is user-readable only
#   - Only staged Git files are scanned
# ============================================================

set -Eeuo pipefail

# ============================================================
# CONFIGURATION
# ============================================================

GITLEAKS_VERSION="8.30.0"

BASE_DIR="$HOME/.security-compliance"

VENV_DIR="$BASE_DIR/venv"
BIN_DIR="$BASE_DIR/bin"
CONFIG_DIR="$BASE_DIR/config"
LOG_DIR="$BASE_DIR/logs"

GLOBAL_HOOK_DIR="$HOME/.git-hooks"
GLOBAL_HOOK="$GLOBAL_HOOK_DIR/pre-commit"

GITLEAKS_CONFIG="$CONFIG_DIR/gitleaks.toml"

TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
LOG_FILE="$LOG_DIR/install-$TIMESTAMP.log"

# ============================================================
# CREATE DIRECTORIES
# ============================================================

mkdir -p \
    "$BIN_DIR" \
    "$CONFIG_DIR" \
    "$LOG_DIR" \
    "$GLOBAL_HOOK_DIR"

chmod 700 "$BASE_DIR"
chmod 700 "$LOG_DIR"
chmod 700 "$CONFIG_DIR"

# ============================================================
# LOGGING
#
# Everything is shown on screen AND saved to a log file.
# ============================================================

exec > >(tee -a "$LOG_FILE") 2>&1

echo
echo "============================================================"
echo "        TEKDI SECURITY COMPLIANCE INSTALLER"
echo "============================================================"
echo
echo "Installation started : $(date)"
echo "Log file              : $LOG_FILE"
echo

# ============================================================
# ERROR HANDLER
# ============================================================

on_error()
{
    local EXIT_CODE=$?

    echo
    echo "============================================================"
    echo "                 INSTALLATION FAILED"
    echo "============================================================"
    echo
    echo "Exit code : $EXIT_CODE"
    echo "Log file  : $LOG_FILE"
    echo
    echo "Please share this log when reporting the issue."
    echo

    exit "$EXIT_CODE"
}

trap on_error ERR

# ============================================================
# FUNCTIONS
# ============================================================

command_exists()
{
    command -v "$1" >/dev/null 2>&1
}

print_section()
{
    echo
    echo "------------------------------------------------------------"
    echo "$1"
    echo "------------------------------------------------------------"
    echo
}

# ============================================================
# OS DETECTION
# ============================================================

print_section "Detecting operating system"

OS="$(uname -s)"
ARCH="$(uname -m)"

echo "Operating system : $OS"
echo "Architecture     : $ARCH"

case "$OS" in

    Linux)
        PLATFORM="linux"
        ;;

    Darwin)
        PLATFORM="darwin"
        ;;

    *)
        echo "ERROR: Unsupported operating system."
        exit 1
        ;;

esac

case "$ARCH" in

    x86_64|amd64)
        CPU_ARCH="x64"
        ;;

    arm64|aarch64)
        CPU_ARCH="arm64"
        ;;

    *)
        echo "ERROR: Unsupported CPU architecture."
        exit 1
        ;;

esac

echo "Platform         : $PLATFORM"
echo "CPU architecture : $CPU_ARCH"

# ============================================================
# SYSTEM DEPENDENCIES - LINUX
# ============================================================

install_linux_dependencies()
{
    print_section "Installing Linux dependencies"

    if ! command_exists sudo; then
        echo "ERROR: sudo is required."
        exit 1
    fi

    if command_exists apt-get; then

        echo "Detected Debian/Ubuntu."

        sudo apt-get update -qq

        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
            ca-certificates \
            curl \
            git \
            openssh-client \
            python3 \
            python3-pip \
            python3-venv \
            jq \
            tmate

        return 0
    fi

    if command_exists dnf; then

        echo "Detected Fedora/RHEL based system."

        sudo dnf install -y -q \
            ca-certificates \
            curl \
            git \
            openssh-clients \
            python3 \
            python3-pip \
            jq \
            tmate

        return 0
    fi

    if command_exists yum; then

        echo "Detected Yum based system."

        sudo yum install -y -q \
            ca-certificates \
            curl \
            git \
            openssh-clients \
            python3 \
            python3-pip \
            jq \
            tmate

        return 0
    fi

    echo "ERROR: Unsupported Linux package manager."
    exit 1
}

# ============================================================
# SYSTEM DEPENDENCIES - MACOS
# ============================================================

install_macos_dependencies()
{
    print_section "Installing macOS dependencies"

    if ! command_exists brew; then
        echo "ERROR: Homebrew is required on macOS."
        echo "Install Homebrew first."
        exit 1
    fi

    brew install \
        git \
        openssh \
        python \
        jq \
        tmate \
        curl \
        >/dev/null 2>&1 || true
}

# ============================================================
# INSTALL SYSTEM DEPENDENCIES
# ============================================================

if [[ "$PLATFORM" == "linux" ]]; then
    install_linux_dependencies
else
    install_macos_dependencies
fi

# ============================================================
# PYTHON ENVIRONMENT
# ============================================================

print_section "Setting up Python environment"

if [[ ! -x "$VENV_DIR/bin/python" ]]; then

    python3 -m venv "$VENV_DIR"

fi

PYTHON="$VENV_DIR/bin/python"
PIP="$VENV_DIR/bin/pip"

echo "Python : $PYTHON"

"$PYTHON" -m pip install --upgrade pip

# ============================================================
# PYTHON SECURITY TOOLS
# ============================================================

print_section "Installing Python security tools"

"$PIP" install --upgrade \
    ansible \
    pre-commit \
    detect-secrets

ln -sf "$VENV_DIR/bin/ansible" \
    "$BIN_DIR/ansible"

ln -sf "$VENV_DIR/bin/ansible-playbook" \
    "$BIN_DIR/ansible-playbook"

ln -sf "$VENV_DIR/bin/pre-commit" \
    "$BIN_DIR/pre-commit"

ln -sf "$VENV_DIR/bin/detect-secrets" \
    "$BIN_DIR/detect-secrets"

# ============================================================
# GITLEAKS
# ============================================================

print_section "Installing Gitleaks"

install_gitleaks()
{
    local VERSION="$1"
    local RELEASE_VERSION="${VERSION#v}"

    local SYSTEM
    local ARCHIVE_ARCH

    if [[ "$PLATFORM" == "linux" ]]; then
        SYSTEM="linux"
    else
        SYSTEM="darwin"
    fi

    case "$CPU_ARCH" in

        x64)
            ARCHIVE_ARCH="x64"
            ;;

        arm64)
            ARCHIVE_ARCH="arm64"
            ;;

        *)
            echo "Unsupported architecture."
            exit 1
            ;;

    esac

    local FILE_NAME
    FILE_NAME="gitleaks_${RELEASE_VERSION}_${SYSTEM}_${ARCHIVE_ARCH}.tar.gz"

    local BASE_URL
    BASE_URL="https://github.com/gitleaks/gitleaks/releases/download/v${RELEASE_VERSION}"

    local TEMP_DIR
    TEMP_DIR="$(mktemp -d)"

    echo "Downloading Gitleaks $VERSION"

    curl -fL \
        "$BASE_URL/$FILE_NAME" \
        -o "$TEMP_DIR/$FILE_NAME"

    echo "Downloading checksum"

    curl -fL \
        "$BASE_URL/gitleaks_${RELEASE_VERSION}_checksums.txt" \
        -o "$TEMP_DIR/checksums.txt"

    echo "Verifying Gitleaks checksum"

    cd "$TEMP_DIR"

    grep " $FILE_NAME\$" checksums.txt | sha256sum -c -

    echo "Extracting Gitleaks"

    tar -xzf "$FILE_NAME"

    install -m 0755 \
        "$TEMP_DIR/gitleaks" \
        "$BIN_DIR/gitleaks"

    rm -rf "$TEMP_DIR"

    echo "Gitleaks installed successfully."
}

CURRENT_GITLEAKS_VERSION=""

if [[ -x "$BIN_DIR/gitleaks" ]]; then

    CURRENT_GITLEAKS_VERSION="$(
        "$BIN_DIR/gitleaks" version 2>/dev/null \
        | awk '{print $NF}' \
        | head -n1
    )"

fi

if [[ "$CURRENT_GITLEAKS_VERSION" != "$GITLEAKS_VERSION" ]]; then

    install_gitleaks "$GITLEAKS_VERSION"

else

    echo "Gitleaks $GITLEAKS_VERSION already installed."

fi

GITLEAKS_BIN="$BIN_DIR/gitleaks"

"$GITLEAKS_BIN" version

# ============================================================
# TRUFFLEHOG
# ============================================================

print_section "Installing TruffleHog"

if command_exists trufflehog; then

    echo "TruffleHog already installed."

else

    if [[ "$PLATFORM" == "darwin" ]]; then

        brew install trufflehog

    else

        curl -fsSL \
            https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh \
            | sudo sh -s -- -b /usr/local/bin

    fi

fi

TRUFFLEHOG_BIN="$(command -v trufflehog)"

"$TRUFFLEHOG_BIN" --version || true

# ============================================================
# GITLEAKS CONFIGURATION
# ============================================================

print_section "Configuring Gitleaks"

if [[ ! -f "$GITLEAKS_CONFIG" ]]; then

cat > "$GITLEAKS_CONFIG" <<'EOF'
title = "Tekdi Security Compliance"

[extend]
useDefault = true

[allowlist]
description = "Approved false positives"

# ============================================================
# FALSE POSITIVE CONFIGURATION
# ============================================================
#
# IMPORTANT:
#
# Do NOT put real credentials here.
#
# Only add confirmed false positives.
#
# Example:
#
# regexes = [
#     '''dummy-test-token-123'''
# ]
#
# Example path exclusion:
#
# paths = [
#     '''(^|/)test/fixtures/'''
# ]
#
# Keep allowlists as narrow as possible.
# ============================================================
EOF

else

    echo "Existing Gitleaks configuration found."
    echo "It will not be overwritten."

fi

chmod 600 "$GITLEAKS_CONFIG"

# ============================================================
# GLOBAL GIT SECURITY HOOK
# ============================================================

print_section "Installing global Git security hook"

cat > "$GLOBAL_HOOK" <<'HOOK'
#!/usr/bin/env bash

set -Eeuo pipefail

export PATH="$HOME/.security-compliance/bin:$HOME/.security-compliance/venv/bin:$PATH"

BASE_DIR="$HOME/.security-compliance"
CONFIG_DIR="$BASE_DIR/config"
LOG_DIR="$BASE_DIR/logs"

GITLEAKS_BIN="$BASE_DIR/bin/gitleaks"
GITLEAKS_CONFIG="$CONFIG_DIR/gitleaks.toml"

TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"

SCAN_LOG="$LOG_DIR/scan-$TIMESTAMP.log"

mkdir -p "$LOG_DIR"

chmod 700 "$LOG_DIR"

exec > >(tee -a "$SCAN_LOG") 2>&1

TMP_DIR="$(mktemp -d)"
SCAN_DIR="$TMP_DIR/staged"

cleanup()
{
    rm -rf "$TMP_DIR" >/dev/null 2>&1 || true
}

trap cleanup EXIT

echo
echo "============================================================"
echo "          TEKDI SECURITY COMPLIANCE SCAN"
echo "============================================================"
echo
echo "Repository : $(git rev-parse --show-toplevel)"
echo "Time       : $(date)"
echo "Scan log   : $SCAN_LOG"
echo

mkdir -p "$SCAN_DIR"

# ============================================================
# STAGED FILES
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

    # Skip submodules.
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

if [[ ! -x "$GITLEAKS_BIN" ]]; then

    echo "ERROR: Gitleaks is not installed."
    echo "COMMIT BLOCKED."

    exit 1

fi

if ! "$GITLEAKS_BIN" dir "$SCAN_DIR" \
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

DETECT_BIN="$BASE_DIR/venv/bin/detect-secrets"

if [[ ! -x "$DETECT_BIN" ]]; then

    echo "ERROR: detect-secrets is not installed."
    echo "COMMIT BLOCKED."

    exit 1

fi

DETECT_OUTPUT="$TMP_DIR/detect-secrets.json"

if ! "$DETECT_BIN" scan "$SCAN_DIR" \
    > "$DETECT_OUTPUT"
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

    print(sum(len(v) for v in results.values()))

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

    exit 1

fi

echo "[OK] detect-secrets passed."

# ============================================================
# TRUFFLEHOG
# ============================================================

echo
echo "[3/3] Running TruffleHog..."

TRUFFLE_BIN="$(command -v trufflehog || true)"

if [[ -z "$TRUFFLE_BIN" ]]; then

    echo "ERROR: TruffleHog is not installed."
    echo "COMMIT BLOCKED."

    exit 1

fi

if ! "$TRUFFLE_BIN" filesystem "$SCAN_DIR" \
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

    exit 1

fi

echo "[OK] TruffleHog passed."

# ============================================================
# SUCCESS
# ============================================================

echo
echo "============================================================"
echo "             SECURITY SCAN PASSED"
echo "============================================================"
echo
echo "No secrets detected."
echo "COMMIT ALLOWED."
echo
echo "Scan log:"
echo "$SCAN_LOG"
echo

exit 0
HOOK

chmod 700 "$GLOBAL_HOOK"

# ============================================================
# GLOBAL GIT CONFIGURATION
# ============================================================

print_section "Configuring Git"

git config --global core.hooksPath "$GLOBAL_HOOK_DIR"

CURRENT_HOOK_PATH="$(
    git config --global --get core.hooksPath
)"

echo "Global Git hook path:"
echo "$CURRENT_HOOK_PATH"

# ============================================================
# VERIFY TOOLS
# ============================================================

print_section "Verifying installation"

export PATH="$BIN_DIR:$VENV_DIR/bin:$PATH"

TOOLS=(
    git
    ssh
    tmate
    ansible
    ansible-playbook
    pre-commit
    detect-secrets
    gitleaks
    trufflehog
)

for TOOL in "${TOOLS[@]}"
do

    if command_exists "$TOOL"; then

        echo "[OK] $TOOL"

    else

        echo "[FAILED] $TOOL"
        exit 1

    fi

done

# ============================================================
# PERSIST PATH
# ============================================================

print_section "Configuring PATH"

SHELL_NAME="$(basename "${SHELL:-bash}")"

case "$SHELL_NAME" in

    bash)
        PROFILE="$HOME/.bashrc"
        ;;

    zsh)
        PROFILE="$HOME/.zshrc"
        ;;

    *)
        PROFILE="$HOME/.profile"
        ;;

esac

PATH_LINE='export PATH="$HOME/.security-compliance/bin:$HOME/.security-compliance/venv/bin:$PATH"'

touch "$PROFILE"

if ! grep -Fq '.security-compliance/bin' "$PROFILE" 2>/dev/null; then

    echo "$PATH_LINE" >> "$PROFILE"

fi

# ============================================================
# FINAL PERMISSIONS
# ============================================================

chmod 700 "$BASE_DIR"
chmod 700 "$CONFIG_DIR"
chmod 700 "$LOG_DIR"
chmod 600 "$GITLEAKS_CONFIG"
chmod 700 "$GLOBAL_HOOK"

# ============================================================
# FINAL RESULT
# ============================================================

echo
echo "============================================================"
echo "       SECURITY COMPLIANCE INSTALLATION COMPLETE"
echo "============================================================"
echo
echo "Installed:"
echo "  ✓ Gitleaks"
echo "  ✓ detect-secrets"
echo "  ✓ TruffleHog"
echo "  ✓ Ansible"
echo "  ✓ pre-commit"
echo "  ✓ OpenSSH client"
echo "  ✓ tmate"
echo
echo "Global Git hook:"
echo "  $GLOBAL_HOOK"
echo
echo "Gitleaks configuration:"
echo "  $GITLEAKS_CONFIG"
echo
echo "Installation log:"
echo "  $LOG_FILE"
echo
echo "Security scan logs:"
echo "  $LOG_DIR/"
echo
echo "============================================================"
echo
echo "Installation completed successfully."
echo
