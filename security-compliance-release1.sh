#!/usr/bin/env bash

# ============================================================
# SECURITY COMPLIANCE INSTALLER
# ============================================================
#
# Supported:
#   - Ubuntu / Debian
#   - Fedora / RHEL / CentOS
#   - macOS Intel
#   - macOS Apple Silicon
#
# Installs:
#   - Git
#   - OpenSSH
#   - tmate
#   - Python
#   - Ansible
#   - detect-secrets
#   - Betterleaks
#   - TruffleHog
#   - pre-commit
#
# Configures:
#   - Global Git pre-commit hook
#   - Secret scanning before every commit
#
# Security scanners:
#   1. detect-secrets
#   2. Betterleaks
#   3. TruffleHog
#
# Behaviour:
#
#   Installation:
#       Full logs visible.
#
#   SUCCESS:
#       Installation log removed.
#       Only success message displayed.
#
#   FAILURE:
#       Installation log retained.
#       Log path displayed.
#
# ============================================================

set -o pipefail

# ============================================================
# CONFIGURATION
# ============================================================

BETTERLEAKS_VERSION="v1.7.2"

VENV_DIR="$HOME/.security-compliance-venv"

USER_BIN="$HOME/.local/bin"

GLOBAL_HOOK_DIR="$HOME/.git-hooks"

GLOBAL_HOOK="$GLOBAL_HOOK_DIR/pre-commit"

LOG_FILE="/tmp/security-compliance-install-$(date +%Y%m%d-%H%M%S).log"

TMP_DIR=""

# ============================================================
# LOGGING
# ============================================================

exec > >(tee -a "$LOG_FILE") 2>&1

echo
echo "============================================================"
echo "        SECURITY COMPLIANCE INSTALLER"
echo "============================================================"
echo
echo "[INFO] Installation log: $LOG_FILE"
echo

# ============================================================
# CLEANUP
# ============================================================

cleanup()
{
    if [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]]; then
        rm -rf "$TMP_DIR" >/dev/null 2>&1 || true
    fi
}

trap cleanup EXIT

# ============================================================
# FAILURE
# ============================================================

failure()
{
    cleanup

    echo
    echo "============================================================"
    echo "Installation failed"
    echo "============================================================"
    echo
    echo "Installation log:"
    echo "$LOG_FILE"
    echo

    exit 1
}

# ============================================================
# SUCCESS
# ============================================================

success()
{
    cleanup

    rm -f "$LOG_FILE" >/dev/null 2>&1 || true

    echo
    echo "Installation completed successfully"

    exit 0
}

# ============================================================
# DETECT OS
# ============================================================

echo "[INFO] Detecting operating system..."

OS="$(uname -s 2>/dev/null)"

ARCH_RAW="$(uname -m 2>/dev/null)"

case "$OS" in

    Linux)
        PLATFORM="linux"
        echo "[OK] Linux detected."
        ;;

    Darwin)
        PLATFORM="macos"
        echo "[OK] macOS detected."
        ;;

    *)
        echo "[ERROR] Unsupported operating system: $OS"
        failure
        ;;

esac

case "$ARCH_RAW" in

    x86_64|amd64)
        ARCH="amd64"
        ;;

    arm64|aarch64)
        ARCH="arm64"
        ;;

    *)
        echo "[ERROR] Unsupported architecture: $ARCH_RAW"
        failure
        ;;

esac

echo "[INFO] Architecture: $ARCH"
echo

# ============================================================
# CREATE DIRECTORIES
# ============================================================

mkdir -p "$USER_BIN" || failure

mkdir -p "$GLOBAL_HOOK_DIR" || failure

# ============================================================
# LINUX PACKAGES
# ============================================================

install_linux_packages()
{
    echo
    echo "------------------------------------------------------------"
    echo "Linux Dependencies"
    echo "------------------------------------------------------------"

    if ! command -v sudo >/dev/null 2>&1; then

        echo "[ERROR] sudo is not installed."

        return 1

    fi

    if command -v apt-get >/dev/null 2>&1; then

        echo "[INFO] Debian/Ubuntu detected."

        sudo apt-get update -qq

        if [[ $? -ne 0 ]]; then
            echo "[ERROR] apt update failed."
            return 1
        fi

        sudo DEBIAN_FRONTEND=noninteractive \
            apt-get install -y -qq \
            curl \
            wget \
            git \
            openssh-client \
            openssh-server \
            tmate \
            python3 \
            python3-pip \
            python3-venv \
            ca-certificates \
            jq \
            golang-go \
            build-essential

        if [[ $? -ne 0 ]]; then
            echo "[ERROR] Linux dependencies installation failed."
            return 1
        fi

        return 0
    fi

    if command -v dnf >/dev/null 2>&1; then

        echo "[INFO] DNF-based Linux detected."

        sudo dnf install -y \
            curl \
            wget \
            git \
            openssh-clients \
            openssh-server \
            tmate \
            python3 \
            python3-pip \
            ca-certificates \
            jq \
            golang \
            gcc \
            make

        if [[ $? -ne 0 ]]; then
            echo "[ERROR] Linux dependencies installation failed."
            return 1
        fi

        return 0
    fi

    if command -v yum >/dev/null 2>&1; then

        echo "[INFO] YUM-based Linux detected."

        sudo yum install -y \
            curl \
            wget \
            git \
            openssh-clients \
            openssh-server \
            tmate \
            python3 \
            python3-pip \
            ca-certificates \
            jq \
            golang \
            gcc \
            make

        if [[ $? -ne 0 ]]; then
            echo "[ERROR] Linux dependencies installation failed."
            return 1
        fi

        return 0
    fi

    echo "[ERROR] No supported Linux package manager found."

    return 1
}

# ============================================================
# MACOS PACKAGES
# ============================================================

install_macos_packages()
{
    echo
    echo "------------------------------------------------------------"
    echo "macOS Dependencies"
    echo "------------------------------------------------------------"

    if ! command -v brew >/dev/null 2>&1; then

        echo "[INFO] Homebrew not found."
        echo "[INFO] Installing Homebrew..."

        NONINTERACTIVE=1 \
        /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

        if [[ $? -ne 0 ]]; then
            echo "[ERROR] Homebrew installation failed."
            return 1
        fi

    fi

    if [[ -x "/opt/homebrew/bin/brew" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi

    if [[ -x "/usr/local/bin/brew" ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi

    if ! command -v brew >/dev/null 2>&1; then

        echo "[ERROR] Homebrew unavailable."

        return 1

    fi

    brew update

    if [[ $? -ne 0 ]]; then
        echo "[ERROR] Homebrew update failed."
        return 1
    fi

    brew install \
        git \
        openssh \
        tmate \
        python \
        jq \
        wget \
        go

    if [[ $? -ne 0 ]]; then

        echo "[ERROR] macOS dependencies installation failed."

        return 1

    fi

    return 0
}

# ============================================================
# INSTALL OS DEPENDENCIES
# ============================================================

if [[ "$PLATFORM" == "linux" ]]; then

    install_linux_packages || failure

else

    install_macos_packages || failure

fi

# ============================================================
# VERIFY BASIC TOOLS
# ============================================================

echo
echo "------------------------------------------------------------"
echo "Verifying Basic Tools"
echo "------------------------------------------------------------"

for TOOL in git ssh tmate python3 curl; do

    if command -v "$TOOL" >/dev/null 2>&1; then

        echo "[OK] $TOOL"

    else

        echo "[ERROR] Missing: $TOOL"

        failure

    fi

done

# ============================================================
# PYTHON VIRTUAL ENVIRONMENT
# ============================================================

echo
echo "------------------------------------------------------------"
echo "Python Security Environment"
echo "------------------------------------------------------------"

if [[ ! -d "$VENV_DIR" ]]; then

    python3 -m venv "$VENV_DIR"

    if [[ $? -ne 0 ]]; then
        echo "[ERROR] Python virtual environment creation failed."
        failure
    fi

fi

export PATH="$VENV_DIR/bin:$USER_BIN:$HOME/go/bin:$PATH"

"$VENV_DIR/bin/python" \
    -m pip install --upgrade pip \
    >/dev/null 2>&1

if [[ $? -ne 0 ]]; then
    echo "[ERROR] pip installation failed."
    failure
fi

# ============================================================
# ANSIBLE
# ============================================================

echo
echo "[INFO] Installing Ansible..."

"$VENV_DIR/bin/python" \
    -m pip install ansible

if [[ $? -ne 0 ]]; then

    echo "[ERROR] Ansible installation failed."

    failure

fi

echo "[OK] Ansible installed."

# ============================================================
# DETECT-SECRETS
# ============================================================

echo
echo "[INFO] Installing detect-secrets..."

"$VENV_DIR/bin/python" \
    -m pip install detect-secrets

if [[ $? -ne 0 ]]; then

    echo "[ERROR] detect-secrets installation failed."

    failure

fi

echo "[OK] detect-secrets installed."

# ============================================================
# PRE-COMMIT
# ============================================================

echo
echo "[INFO] Installing pre-commit..."

"$VENV_DIR/bin/python" \
    -m pip install pre-commit

if [[ $? -ne 0 ]]; then

    echo "[ERROR] pre-commit installation failed."

    failure

fi

echo "[OK] pre-commit installed."

# ============================================================
# PYTHON LINKS
# ============================================================

ln -sf "$VENV_DIR/bin/ansible" \
    "$USER_BIN/ansible"

ln -sf "$VENV_DIR/bin/ansible-playbook" \
    "$USER_BIN/ansible-playbook"

ln -sf "$VENV_DIR/bin/detect-secrets" \
    "$USER_BIN/detect-secrets"

ln -sf "$VENV_DIR/bin/pre-commit" \
    "$USER_BIN/pre-commit"

# ============================================================
# BETTERLEAKS
# ============================================================

echo
echo "------------------------------------------------------------"
echo "Betterleaks"
echo "------------------------------------------------------------"

if [[ "$PLATFORM" == "macos" ]]; then

    echo "[INFO] Installing Betterleaks..."

    brew install betterleaks

    if [[ $? -ne 0 ]]; then

        echo "[ERROR] Betterleaks installation failed."

        failure

    fi

else

    if ! command -v go >/dev/null 2>&1; then

        echo "[ERROR] Go is not available."

        failure

    fi

    export GOPATH="${GOPATH:-$HOME/go}"

    mkdir -p "$GOPATH/bin"

    export PATH="$GOPATH/bin:$PATH"

    echo "[INFO] Installing Betterleaks $BETTERLEAKS_VERSION..."

    go install \
        "github.com/betterleaks/betterleaks@${BETTERLEAKS_VERSION}"

    if [[ $? -ne 0 ]]; then

        echo "[ERROR] Betterleaks installation failed."

        failure

    fi

    if [[ ! -f "$GOPATH/bin/betterleaks" ]]; then

        echo "[ERROR] Betterleaks binary missing."

        failure

    fi

    chmod +x "$GOPATH/bin/betterleaks"

    ln -sf \
        "$GOPATH/bin/betterleaks" \
        "$USER_BIN/betterleaks"

fi

echo "[OK] Betterleaks installed."

# ============================================================
# TRUFFLEHOG
# ============================================================

echo
echo "------------------------------------------------------------"
echo "TruffleHog"
echo "------------------------------------------------------------"

if [[ "$PLATFORM" == "macos" ]]; then

    brew install trufflehog

    if [[ $? -ne 0 ]]; then

        echo "[ERROR] TruffleHog installation failed."

        failure

    fi

else

    if command -v trufflehog >/dev/null 2>&1; then

        echo "[OK] Existing TruffleHog found."

    else

        echo "[INFO] Installing TruffleHog..."

        curl -sSfL \
            https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh \
            | sudo sh -s -- -b /usr/local/bin

        if [[ ${PIPESTATUS[0]} -ne 0 ]]; then

            echo "[ERROR] TruffleHog installation failed."

            failure

        fi

    fi

fi

echo "[OK] TruffleHog installed."

# ============================================================
# GLOBAL GIT HOOK
# ============================================================

echo
echo "------------------------------------------------------------"
echo "Global Git Security Hook"
echo "------------------------------------------------------------"

cat > "$GLOBAL_HOOK" <<'HOOK'
#!/usr/bin/env bash

# ============================================================
# GLOBAL GIT SECRET SECURITY HOOK
# ============================================================

export PATH="$HOME/.security-compliance-venv/bin:$HOME/.local/bin:$HOME/go/bin:$PATH"

TMP_DIR="$(mktemp -d)"

cleanup()
{
    rm -rf "$TMP_DIR"
}

trap cleanup EXIT

echo
echo "=================================================="
echo "       SECURITY COMPLIANCE SECRET SCAN"
echo "=================================================="
echo
echo "Scanning staged changes..."
echo

SCAN_DIR="$TMP_DIR/staged"

mkdir -p "$SCAN_DIR"

FOUND_FILES=0

STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACMR)

if [[ -z "$STAGED_FILES" ]]; then

    echo "[OK] No staged files."
    exit 0

fi

while IFS= read -r FILE
do

    [[ -z "$FILE" ]] && continue

    # --------------------------------------------------------
    # Detect Git submodule
    # --------------------------------------------------------

    MODE=$(git ls-files -s -- "$FILE" 2>/dev/null | awk '{print $1}')

    if [[ "$MODE" == "160000" ]]; then

        echo "[INFO] Git submodule skipped: $FILE"

        continue

    fi

    # --------------------------------------------------------
    # Make sure staged object exists
    # --------------------------------------------------------

    if ! git cat-file -e ":$FILE" 2>/dev/null; then

        continue

    fi

    mkdir -p "$SCAN_DIR/$(dirname "$FILE")"

    if git show ":$FILE" > "$SCAN_DIR/$FILE" 2>/dev/null; then

        FOUND_FILES=$((FOUND_FILES + 1))

    fi

done <<< "$STAGED_FILES"

if [[ "$FOUND_FILES" -eq 0 ]]; then

    echo
    echo "[OK] No readable staged files."
    echo "[OK] Secret scan passed."

    exit 0

fi

# ============================================================
# DETECT-SECRETS
# ============================================================

echo
echo "[INFO] Running detect-secrets..."

DETECT_OUTPUT="$TMP_DIR/detect.json"

detect-secrets scan "$SCAN_DIR" > "$DETECT_OUTPUT" 2>/dev/null

DETECT_COUNT=$(python3 - "$DETECT_OUTPUT" <<'PY'
import json
import sys

try:
    with open(sys.argv[1]) as f:
        data = json.load(f)

    count = sum(
        len(v)
        for v in data.get("results", {}).values()
    )

    print(count)

except Exception:
    print(0)
PY
)

if [[ "$DETECT_COUNT" -gt 0 ]]; then

    echo
    echo "=================================================="
    echo "             SECRET DETECTED"
    echo "=================================================="
    echo
    echo "detect-secrets found potential secret(s)."
    echo
    echo "Commit blocked."
    echo
    echo "Remove the secret and try again."
    echo

    exit 1

fi

echo "[OK] detect-secrets passed."

# ============================================================
# BETTERLEAKS
# ============================================================

echo
echo "[INFO] Running Betterleaks..."

BETTER_OUTPUT="$TMP_DIR/betterleaks.txt"

betterleaks dir "$SCAN_DIR" --redact \
    > "$BETTER_OUTPUT" 2>&1

if grep -qiE \
    "leak found|leaks found|secret found|finding" \
    "$BETTER_OUTPUT"; then

    echo
    echo "=================================================="
    echo "             SECRET DETECTED"
    echo "=================================================="
    echo
    echo "Betterleaks found a potential secret."
    echo
    echo "Commit blocked."
    echo
    echo "Remove the secret and try again."
    echo

    exit 1

fi

echo "[OK] Betterleaks passed."

# ============================================================
# TRUFFLEHOG
# ============================================================

echo
echo "[INFO] Running TruffleHog..."

TRUFFLE_OUTPUT="$TMP_DIR/trufflehog.txt"

trufflehog filesystem "$SCAN_DIR" \
    --no-update \
    --no-verification \
    > "$TRUFFLE_OUTPUT" 2>&1

if grep -qiE \
    "Found.*result|Found.*secret|verified result|unverified result" \
    "$TRUFFLE_OUTPUT"; then

    echo
    echo "=================================================="
    echo "             SECRET DETECTED"
    echo "=================================================="
    echo
    echo "TruffleHog found a potential secret."
    echo
    echo "Commit blocked."
    echo
    echo "Remove the secret and try again."
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
echo "Commit allowed."
echo

exit 0
HOOK

chmod +x "$GLOBAL_HOOK"

if [[ $? -ne 0 ]]; then

    echo "[ERROR] Could not create global Git hook."

    failure

fi

echo "[OK] Global Git hook created."

# ============================================================
# CONFIGURE GIT
# ============================================================

echo
echo "[INFO] Configuring Git global hooks path..."

git config --global core.hooksPath "$GLOBAL_HOOK_DIR"

if [[ $? -ne 0 ]]; then

    echo "[ERROR] Could not configure Git hooks path."

    failure

fi

echo "[OK] Global Git hook configured."

# ============================================================
# VERIFY GIT CONFIGURATION
# ============================================================

HOOK_PATH="$(git config --global --get core.hooksPath)"

if [[ "$HOOK_PATH" != "$GLOBAL_HOOK_DIR" ]]; then

    echo "[ERROR] Git hooks path verification failed."

    failure

fi

# ============================================================
# SECURITY TEST
# ============================================================

echo
echo "------------------------------------------------------------"
echo "Security Scanner Verification"
echo "------------------------------------------------------------"

TMP_TEST="$TMP_DIR"

if [[ -z "$TMP_TEST" ]]; then

    TMP_TEST="$(mktemp -d)"

fi

TEST_FILE="$TMP_TEST/security-test.env"

cat > "$TEST_FILE" <<'EOF'
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
EOF

# ------------------------------------------------------------
# detect-secrets verification
# ------------------------------------------------------------

detect-secrets scan "$TEST_FILE" \
    > "$TMP_TEST/detect-test.json" \
    2>/dev/null

DETECT_TEST_COUNT=$(python3 - "$TMP_TEST/detect-test.json" <<'PY'
import json
import sys

try:
    with open(sys.argv[1]) as f:
        data = json.load(f)

    print(
        sum(
            len(v)
            for v in data.get("results", {}).values()
        )
    )

except Exception:
    print(0)
PY
)

if [[ "$DETECT_TEST_COUNT" -eq 0 ]]; then

    echo "[ERROR] detect-secrets test failed."

    failure

fi

echo "[OK] detect-secrets verification passed."

# ------------------------------------------------------------
# Betterleaks verification
# ------------------------------------------------------------

betterleaks dir "$TEST_FILE" --redact \
    > "$TMP_TEST/better-test.txt" \
    2>&1

if grep -qiE \
    "error|panic|fatal" \
    "$TMP_TEST/better-test.txt"; then

    echo "[ERROR] Betterleaks execution failed."

    failure

fi

echo "[OK] Betterleaks execution verified."

# ------------------------------------------------------------
# TruffleHog verification
# ------------------------------------------------------------

trufflehog filesystem "$TEST_FILE" \
    --no-update \
    --no-verification \
    > "$TMP_TEST/truffle-test.txt" \
    2>&1

TRUFFLE_STATUS=$?

if [[ "$TRUFFLE_STATUS" -ne 0 ]]; then

    echo "[ERROR] TruffleHog verification failed."

    failure

fi

echo "[OK] TruffleHog execution verified."

# ============================================================
# FINAL TOOL VERIFICATION
# ============================================================

echo
echo "------------------------------------------------------------"
echo "Final Tool Verification"
echo "------------------------------------------------------------"

for TOOL in \
    git \
    ssh \
    tmate \
    ansible \
    ansible-playbook \
    detect-secrets \
    pre-commit \
    betterleaks \
    trufflehog
do

    if command -v "$TOOL" >/dev/null 2>&1; then

        echo "[OK] $TOOL"

    else

        echo "[ERROR] $TOOL missing."

        failure

    fi

done

# ============================================================
# SHELL PATH
# ============================================================

SHELL_NAME="$(basename "${SHELL:-bash}")"

case "$SHELL_NAME" in

    zsh)
        PROFILE="$HOME/.zshrc"
        ;;

    bash)
        PROFILE="$HOME/.bashrc"
        ;;

    *)
        PROFILE="$HOME/.profile"
        ;;

esac

PATH_LINE='export PATH="$HOME/.security-compliance-venv/bin:$HOME/.local/bin:$HOME/go/bin:$PATH"'

if ! grep -Fq \
    '.security-compliance-venv/bin' \
    "$PROFILE" \
    2>/dev/null; then

    echo "$PATH_LINE" >> "$PROFILE"

fi

# ============================================================
# FINAL SUCCESS
# ============================================================

echo
echo "============================================================"
echo "       SECURITY COMPLIANCE SETUP COMPLETE"
echo "============================================================"
echo
echo "[OK] Security tools installed."
echo "[OK] Global Git pre-commit hook installed."
echo "[OK] Secret scanning enabled."
echo "[OK] Git submodule handling enabled."
echo "[OK] Commit blocking enabled."
echo

success
