#!/usr/bin/env bash

# ============================================================
# TEKDI SECURITY COMPLIANCE INSTALLER
#
# Installs and configures:
#   - Gitleaks
#   - detect-secrets
#   - TruffleHog
#   - Ansible
#   - OpenSSH client
#   - tmate
#
# Configures a global Git pre-commit hook that scans staged
# files before allowing a commit.
#
# No source code or scan results are uploaded anywhere.
# ============================================================

set -Eeuo pipefail

# ============================================================
# CONFIGURATION
# ============================================================

GITLEAKS_VERSION="8.30.0"

VENV_DIR="$HOME/.security-compliance-venv"
USER_BIN="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/security-compliance"

GLOBAL_HOOK_DIR="$HOME/.git-hooks"
GLOBAL_HOOK="$GLOBAL_HOOK_DIR/pre-commit"

GITLEAKS_CONFIG="$CONFIG_DIR/gitleaks.toml"

LOG_FILE="/tmp/security-compliance-install-$(date +%Y%m%d-%H%M%S).log"

# ============================================================
# TERMINAL / LOGGING
# ============================================================

exec 3>&1
exec >"$LOG_FILE" 2>&1

cleanup_install()
{
    rm -f "$LOG_FILE" >/dev/null 2>&1 || true
}

fail()
{
    cleanup_install

    printf '%s\n' "Installation failed." >&3
    printf '%s\n' "Check the installation requirements and try again." >&3

    exit 1
}

success()
{
    cleanup_install

    printf '%s\n' "Installation completed successfully." >&3
    printf '%s\n' "Security scanning is now enabled for Git commits." >&3

    exit 0
}

trap fail ERR

# ============================================================
# FUNCTIONS
# ============================================================

command_exists()
{
    command -v "$1" >/dev/null 2>&1
}

# ============================================================
# OS / ARCHITECTURE
# ============================================================

OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
    Linux)
        PLATFORM="linux"
        ;;
    Darwin)
        PLATFORM="darwin"
        ;;
    *)
        fail
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
        fail
        ;;
esac

# ============================================================
# DIRECTORIES
# ============================================================

mkdir -p \
    "$USER_BIN" \
    "$CONFIG_DIR" \
    "$GLOBAL_HOOK_DIR"

# ============================================================
# SYSTEM DEPENDENCIES
# ============================================================

install_linux_dependencies()
{
    command_exists sudo || fail

    if command_exists apt-get; then

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
            tmate \
            >/dev/null

        return 0
    fi

    if command_exists dnf; then

        sudo dnf install -y -q \
            ca-certificates \
            curl \
            git \
            openssh-clients \
            python3 \
            python3-pip \
            jq \
            tmate \
            >/dev/null

        return 0
    fi

    if command_exists yum; then

        sudo yum install -y -q \
            ca-certificates \
            curl \
            git \
            openssh-clients \
            python3 \
            python3-pip \
            jq \
            tmate \
            >/dev/null

        return 0
    fi

    fail
}

install_macos_dependencies()
{
    if ! command_exists brew; then
        fail
    fi

    brew update >/dev/null

    brew install \
        git \
        openssh \
        python \
        jq \
        tmate \
        curl \
        >/dev/null 2>&1 || true
}

if [[ "$PLATFORM" == "linux" ]]; then
    install_linux_dependencies
else
    install_macos_dependencies
fi

# ============================================================
# PYTHON VIRTUAL ENVIRONMENT
# ============================================================

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    python3 -m venv "$VENV_DIR"
fi

PYTHON="$VENV_DIR/bin/python"
PIP="$VENV_DIR/bin/pip"

"$PYTHON" -m pip install --upgrade pip >/dev/null 2>&1

# ============================================================
# PYTHON SECURITY TOOLS
# ============================================================

"$PIP" install \
    --upgrade \
    ansible \
    pre-commit \
    detect-secrets \
    >/dev/null 2>&1

ln -sf "$VENV_DIR/bin/ansible" \
    "$USER_BIN/ansible"

ln -sf "$VENV_DIR/bin/ansible-playbook" \
    "$USER_BIN/ansible-playbook"

ln -sf "$VENV_DIR/bin/pre-commit" \
    "$USER_BIN/pre-commit"

ln -sf "$VENV_DIR/bin/detect-secrets" \
    "$USER_BIN/detect-secrets"

# ============================================================
# GITLEAKS
# ============================================================

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
            fail
            ;;
    esac

    local FILE_NAME
    FILE_NAME="gitleaks_${RELEASE_VERSION}_${SYSTEM}_${ARCHIVE_ARCH}.tar.gz"

    local BASE_URL
    BASE_URL="https://github.com/gitleaks/gitleaks/releases/download/v${RELEASE_VERSION}"

    local TMP_DIR
    TMP_DIR="$(mktemp -d)"

    cleanup_gitleaks()
    {
        rm -rf "$TMP_DIR"
    }

    trap cleanup_gitleaks RETURN

    curl -fsSL \
        "$BASE_URL/$FILE_NAME" \
        -o "$TMP_DIR/$FILE_NAME"

    curl -fsSL \
        "$BASE_URL/gitleaks_${RELEASE_VERSION}_checksums.txt" \
        -o "$TMP_DIR/checksums.txt"

    cd "$TMP_DIR"

    grep " $FILE_NAME\$" checksums.txt | sha256sum -c -

    tar -xzf "$FILE_NAME"

    install -m 0755 \
        "$TMP_DIR/gitleaks" \
        "$USER_BIN/gitleaks"

    "$USER_BIN/gitleaks" version >/dev/null
}

CURRENT_GITLEAKS_VERSION=""

if command_exists gitleaks; then
    CURRENT_GITLEAKS_VERSION="$(
        gitleaks version 2>/dev/null \
        | awk '{print $NF}' \
        | head -n1
    )"
fi

if [[ "$CURRENT_GITLEAKS_VERSION" != "$GITLEAKS_VERSION" ]]; then
    install_gitleaks "$GITLEAKS_VERSION"
fi

GITLEAKS_BIN="$USER_BIN/gitleaks"

[[ -x "$GITLEAKS_BIN" ]] || fail

# ============================================================
# TRUFFLEHOG
# ============================================================

install_trufflehog()
{
    if command_exists trufflehog; then
        return 0
    fi

    if [[ "$PLATFORM" == "darwin" ]]; then

        brew install trufflehog >/dev/null 2>&1

    else

        curl -fsSL \
            https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh \
            | sudo sh -s -- -b /usr/local/bin

    fi
}

install_trufflehog

TRUFFLEHOG_BIN="$(command -v trufflehog)"

"$TRUFFLEHOG_BIN" --help >/dev/null 2>&1

# ============================================================
# GITLEAKS CONFIGURATION
# ============================================================

if [[ ! -f "$GITLEAKS_CONFIG" ]]; then

cat > "$GITLEAKS_CONFIG" <<'EOF'
title = "Tekdi Security Compliance - Gitleaks Configuration"

[extend]
useDefault = true

[allowlist]
description = "Approved false positives only"

# Add narrowly-scoped approved test values here.
#
# Example:
#
# regexes = [
#     '''dummy-test-secret-123'''
# ]
#
# Do NOT add real credentials or broad patterns here.
#
# Paths can also be excluded when they are known to contain
# documentation/test fixtures:
#
# paths = [
#     '''(^|/)test/fixtures/'''
# ]
EOF

fi

chmod 600 "$GITLEAKS_CONFIG"

# ============================================================
# GLOBAL GIT SECURITY HOOK
# ============================================================

cat > "$GLOBAL_HOOK" <<'HOOK'
#!/usr/bin/env bash

set -Eeuo pipefail

export PATH="$HOME/.security-compliance-venv/bin:$HOME/.local/bin:$PATH"

CONFIG_DIR="$HOME/.config/security-compliance"
GITLEAKS_CONFIG="$CONFIG_DIR/gitleaks.toml"

TMP_DIR="$(mktemp -d)"
SCAN_DIR="$TMP_DIR/staged"

cleanup()
{
    rm -rf "$TMP_DIR" >/dev/null 2>&1 || true
}

trap cleanup EXIT

echo
echo "=================================================="
echo "       TEKDI SECURITY COMPLIANCE SCAN"
echo "=================================================="
echo
echo "Scanning staged files..."
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

    # Skip Git submodules.
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
    exit 0
fi

# ============================================================
# GITLEAKS
# ============================================================

echo
echo "[1/3] Running Gitleaks..."

GITLEAKS_BIN="$HOME/.local/bin/gitleaks"

if [[ ! -x "$GITLEAKS_BIN" ]]; then

    echo
    echo "ERROR: Gitleaks is not installed."
    echo "COMMIT BLOCKED."

    exit 1

fi

if ! "$GITLEAKS_BIN" dir "$SCAN_DIR" \
    --config "$GITLEAKS_CONFIG" \
    --redact \
    >/dev/null 2>&1
then

    echo
    echo "=================================================="
    echo "             GITLEAKS DETECTION"
    echo "=================================================="
    echo
    echo "Gitleaks detected a potential secret."
    echo
    echo "COMMIT BLOCKED."
    echo
    echo "If this is a confirmed false positive,"
    echo "update the approved Gitleaks configuration."
    echo

    exit 1
fi

echo "[OK] Gitleaks passed."

# ============================================================
# DETECT-SECRETS
# ============================================================

echo
echo "[2/3] Running detect-secrets..."

DETECT_BIN="$HOME/.security-compliance-venv/bin/detect-secrets"

if [[ ! -x "$DETECT_BIN" ]]; then

    echo
    echo "ERROR: detect-secrets is not installed."
    echo "COMMIT BLOCKED."

    exit 1

fi

DETECT_OUTPUT="$TMP_DIR/detect-secrets.json"

if ! "$DETECT_BIN" scan "$SCAN_DIR" \
    > "$DETECT_OUTPUT" 2>/dev/null
then

    echo
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
    echo "=================================================="
    echo "          DETECT-SECRETS DETECTION"
    echo "=================================================="
    echo
    echo "Potential secret(s) detected."
    echo
    echo "COMMIT BLOCKED."
    echo
    echo "Remove the secret and try again."
    echo

    exit 1

fi

echo "[OK] detect-secrets passed."

# ============================================================
# TRUFFLEHOG
# ============================================================

echo
echo "[3/3] Running TruffleHog..."

TRUFFLE_BIN="$(
    command -v trufflehog 2>/dev/null || true
)"

if [[ -z "$TRUFFLE_BIN" ]]; then

    echo
    echo "ERROR: TruffleHog is not installed."
    echo "COMMIT BLOCKED."

    exit 1

fi

if ! "$TRUFFLE_BIN" filesystem "$SCAN_DIR" \
    --no-update \
    --no-verification \
    >/dev/null 2>&1
then

    echo
    echo "=================================================="
    echo "          TRUFFLEHOG DETECTION"
    echo "=================================================="
    echo
    echo "TruffleHog detected a potential secret."
    echo
    echo "COMMIT BLOCKED."
    echo

    exit 1
fi

echo "[OK] TruffleHog passed."

# ============================================================
# SUCCESS
# ============================================================

echo
echo "=================================================="
echo "          SECURITY SCAN PASSED"
echo "=================================================="
echo
echo "No secrets detected."
echo "COMMIT ALLOWED."
echo

exit 0
HOOK

chmod 700 "$GLOBAL_HOOK"

# ============================================================
# GLOBAL GIT HOOK CONFIGURATION
# ============================================================

git config --global core.hooksPath "$GLOBAL_HOOK_DIR"

[[ "$(git config --global --get core.hooksPath)" == "$GLOBAL_HOOK_DIR" ]]

# ============================================================
# VERIFY INSTALLATION
# ============================================================

export PATH="$VENV_DIR/bin:$USER_BIN:$PATH"

REQUIRED_TOOLS=(
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

for TOOL in "${REQUIRED_TOOLS[@]}"
do
    command_exists "$TOOL" || fail
done

# ============================================================
# PERSIST PATH
# ============================================================

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

PATH_LINE='export PATH="$HOME/.security-compliance-venv/bin:$HOME/.local/bin:$PATH"'

touch "$PROFILE"

if ! grep -Fq '.security-compliance-venv/bin' "$PROFILE" 2>/dev/null; then
    printf '%s\n' "$PATH_LINE" >> "$PROFILE"
fi

# ============================================================
# FINAL SECURITY CHECK
# ============================================================

[[ -x "$GLOBAL_HOOK" ]]
[[ -x "$GITLEAKS_BIN" ]]
[[ -f "$GITLEAKS_CONFIG" ]]

# Ensure configuration cannot be modified by other users.
chmod 700 "$CONFIG_DIR"
chmod 600 "$GITLEAKS_CONFIG"

# ============================================================
# COMPLETE
# ============================================================

success
