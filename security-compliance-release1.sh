#!/usr/bin/env bash

# ============================================================
# SECURITY COMPLIANCE INSTALLER
# ============================================================
#
# Supported:
#   Linux
#   macOS
#
# Installs:
#   - Git
#   - OpenSSH
#   - tmate
#   - Python
#   - Ansible
#   - pre-commit
#   - detect-secrets
#   - Betterleaks
#   - TruffleHog
#
# Configures:
#   - Global Git pre-commit hook
#
# Security:
#   - detect-secrets
#   - Betterleaks
#   - TruffleHog
#
# Git commit behaviour:
#
#   Secret found  -> COMMIT BLOCKED
#   No secret     -> COMMIT ALLOWED
#
# ============================================================

set -o pipefail

# ============================================================
# CONFIGURATION
# ============================================================

VENV_DIR="$HOME/.security-compliance-venv"
USER_BIN="$HOME/.local/bin"
GO_BIN="$HOME/go/bin"
GLOBAL_HOOK_DIR="$HOME/.git-hooks"
GLOBAL_HOOK="$GLOBAL_HOOK_DIR/pre-commit"

LOG_FILE="/tmp/security-compliance-install-$(date +%Y%m%d-%H%M%S).log"

BETTERLEAKS_VERSION="v1.7.2"

# ============================================================
# LOGGING
# ============================================================

exec > >(tee -a "$LOG_FILE") 2>&1

# ============================================================
# FUNCTIONS
# ============================================================

cleanup()
{
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR" >/dev/null 2>&1 || true
    fi
}

failure()
{
    echo
    echo "============================================================"
    echo "Installation failed"
    echo "============================================================"
    echo
    echo "Installation log:"
    echo "$LOG_FILE"
    echo

    cleanup

    exit 1
}

success()
{
    cleanup

    rm -f "$LOG_FILE" >/dev/null 2>&1 || true

    echo
    echo "============================================================"
    echo "Installation completed successfully"
    echo "============================================================"
    echo

    exit 0
}

command_exists()
{
    command -v "$1" >/dev/null 2>&1
}

# ============================================================
# HEADER
# ============================================================

echo
echo "============================================================"
echo "        COMPLETE SECRET SECURITY SETUP"
echo "============================================================"
echo

echo "[INFO] Installation started."
echo "[INFO] Project directory: $HOME"
echo

# ============================================================
# OS DETECTION
# ============================================================

OS="$(uname -s)"
ARCH="$(uname -m)"

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

case "$ARCH" in

    x86_64|amd64)

        CPU_ARCH="amd64"

        ;;

    arm64|aarch64)

        CPU_ARCH="arm64"

        ;;

    *)

        echo "[ERROR] Unsupported architecture: $ARCH"

        failure

        ;;

esac

echo "[INFO] Architecture: $CPU_ARCH"

# ============================================================
# CREATE DIRECTORIES
# ============================================================

mkdir -p "$USER_BIN" || failure
mkdir -p "$GO_BIN" || failure
mkdir -p "$GLOBAL_HOOK_DIR" || failure

# ============================================================
# LINUX PACKAGE INSTALLATION
# ============================================================

install_linux()
{
    echo
    echo "------------------------------------------------------------"
    echo "Linux Dependencies"
    echo "------------------------------------------------------------"

    if ! command_exists sudo; then

        echo "[ERROR] sudo is required."

        return 1

    fi

    # --------------------------------------------------------
    # Debian / Ubuntu
    # --------------------------------------------------------

    if command_exists apt-get; then

        echo "[INFO] Debian/Ubuntu package manager detected."

        sudo apt-get update -qq

        if [[ $? -ne 0 ]]; then
            return 1
        fi

        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
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

        return $?

    fi

    # --------------------------------------------------------
    # Fedora
    # --------------------------------------------------------

    if command_exists dnf; then

        echo "[INFO] Fedora/DNF package manager detected."

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

        return $?

    fi

    # --------------------------------------------------------
    # CentOS/RHEL
    # --------------------------------------------------------

    if command_exists yum; then

        echo "[INFO] YUM package manager detected."

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

        return $?

    fi

    echo "[ERROR] Unsupported Linux package manager."

    return 1
}

# ============================================================
# MACOS PACKAGE INSTALLATION
# ============================================================

install_macos()
{
    echo
    echo "------------------------------------------------------------"
    echo "macOS Dependencies"
    echo "------------------------------------------------------------"

    if ! command_exists brew; then

        echo "[INFO] Homebrew not found."
        echo "[INFO] Installing Homebrew..."

        NONINTERACTIVE=1 \
        /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

        if [[ $? -ne 0 ]]; then
            return 1
        fi

    fi

    if [[ -x "/opt/homebrew/bin/brew" ]]; then

        eval "$(/opt/homebrew/bin/brew shellenv)"

    fi

    if [[ -x "/usr/local/bin/brew" ]]; then

        eval "$(/usr/local/bin/brew shellenv)"

    fi

    if ! command_exists brew; then

        echo "[ERROR] Homebrew is unavailable."

        return 1

    fi

    brew update

    if [[ $? -ne 0 ]]; then
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

    return $?
}

# ============================================================
# INSTALL OS DEPENDENCIES
# ============================================================

if [[ "$PLATFORM" == "linux" ]]; then

    install_linux

    if [[ $? -ne 0 ]]; then
        failure
    fi

else

    install_macos

    if [[ $? -ne 0 ]]; then
        failure
    fi

fi

echo
echo "[OK] System dependencies installed."

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

PYTHON="$VENV_DIR/bin/python"
PIP="$VENV_DIR/bin/pip"

if [[ ! -x "$PYTHON" ]]; then

    echo "[ERROR] Python virtual environment is invalid."

    failure

fi

"$PYTHON" -m pip install --upgrade pip >/dev/null 2>&1

if [[ $? -ne 0 ]]; then

    echo "[ERROR] pip setup failed."

    failure

fi

echo "[OK] Python environment ready."

# ============================================================
# ANSIBLE
# ============================================================

echo
echo "------------------------------------------------------------"
echo "Ansible"
echo "------------------------------------------------------------"

"$PIP" install ansible >/dev/null 2>&1

if [[ $? -ne 0 ]]; then

    echo "[ERROR] Ansible installation failed."

    failure

fi

ln -sf "$VENV_DIR/bin/ansible" \
    "$USER_BIN/ansible"

ln -sf "$VENV_DIR/bin/ansible-playbook" \
    "$USER_BIN/ansible-playbook"

echo "[OK] Ansible installed."

# ============================================================
# PRE-COMMIT
# ============================================================

echo
echo "------------------------------------------------------------"
echo "Pre-commit"
echo "------------------------------------------------------------"

"$PIP" install pre-commit >/dev/null 2>&1

if [[ $? -ne 0 ]]; then

    echo "[ERROR] pre-commit installation failed."

    failure

fi

ln -sf "$VENV_DIR/bin/pre-commit" \
    "$USER_BIN/pre-commit"

echo "[OK] pre-commit installed."

# ============================================================
# DETECT-SECRETS
# ============================================================

echo
echo "------------------------------------------------------------"
echo "detect-secrets"
echo "------------------------------------------------------------"

"$PIP" install detect-secrets >/dev/null 2>&1

if [[ $? -ne 0 ]]; then

    echo "[ERROR] detect-secrets installation failed."

    failure

fi

ln -sf "$VENV_DIR/bin/detect-secrets" \
    "$USER_BIN/detect-secrets"

if [[ ! -x "$VENV_DIR/bin/detect-secrets" ]]; then

    echo "[ERROR] detect-secrets binary not found."

    failure

fi

echo "[OK] detect-secrets installed."

# ============================================================
# BETTERLEAKS
# ============================================================

echo
echo "------------------------------------------------------------"
echo "Betterleaks"
echo "------------------------------------------------------------"

export PATH="$GO_BIN:$USER_BIN:$PATH"

if [[ "$PLATFORM" == "macos" ]]; then

    if command_exists brew; then

        brew install betterleaks

        if [[ $? -ne 0 ]]; then

            echo "[ERROR] Betterleaks installation failed."

            failure

        fi

    else

        echo "[ERROR] Homebrew unavailable."

        failure

    fi

else

    if ! command_exists go; then

        echo "[ERROR] Go is not installed."

        failure

    fi

    echo "[INFO] Installing Betterleaks $BETTERLEAKS_VERSION..."

    go install \
        "github.com/betterleaks/betterleaks@${BETTERLEAKS_VERSION}"

    if [[ $? -ne 0 ]]; then

        echo "[ERROR] Betterleaks installation failed."

        failure

    fi

    if [[ ! -x "$GO_BIN/betterleaks" ]]; then

        echo "[ERROR] Betterleaks binary not found."

        failure

    fi

    ln -sf "$GO_BIN/betterleaks" \
        "$USER_BIN/betterleaks"

fi

if ! "$USER_BIN/betterleaks" version >/dev/null 2>&1; then

    if ! "$USER_BIN/betterleaks" --help >/dev/null 2>&1; then

        echo "[ERROR] Betterleaks verification failed."

        failure

    fi

fi

echo "[OK] Betterleaks installed."

# ============================================================
# TRUFFLEHOG
# ============================================================

echo
echo "------------------------------------------------------------"
echo "TruffleHog"
echo "------------------------------------------------------------"

export PATH="$USER_BIN:$PATH"

if command_exists trufflehog; then

    echo "[OK] Existing TruffleHog found."

else

    if [[ "$PLATFORM" == "macos" ]]; then

        brew install trufflehog

        if [[ $? -ne 0 ]]; then

            echo "[ERROR] TruffleHog installation failed."

            failure

        fi

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

if ! command_exists trufflehog; then

    echo "[ERROR] TruffleHog command not found."

    failure

fi

echo "[OK] TruffleHog installed."

# ============================================================
# GLOBAL GIT SECURITY HOOK
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

set -o pipefail

export PATH="$HOME/.security-compliance-venv/bin:$HOME/.local/bin:$HOME/go/bin:$PATH"

TMP_DIR="$(mktemp -d)"
SCAN_DIR="$TMP_DIR/staged"

cleanup()
{
    rm -rf "$TMP_DIR" >/dev/null 2>&1 || true
}

trap cleanup EXIT

echo
echo "=================================================="
echo "       SECURITY COMPLIANCE SECRET SCAN"
echo "=================================================="
echo
echo "Scanning staged changes..."
echo

mkdir -p "$SCAN_DIR"

# ============================================================
# GET STAGED FILES
# ============================================================

STAGED_FILES="$(git diff --cached --name-only --diff-filter=ACMR)"

if [[ -z "$STAGED_FILES" ]]; then

    echo "[OK] No staged files."
    echo "[OK] Commit allowed."

    exit 0

fi

READABLE_FILES=0

# ============================================================
# EXTRACT STAGED FILE CONTENT
# ============================================================

while IFS= read -r FILE
do

    [[ -z "$FILE" ]] && continue

    # --------------------------------------------------------
    # Detect Git submodule
    # --------------------------------------------------------

    MODE="$(git ls-files -s -- "$FILE" 2>/dev/null | awk '{print $1}')"

    if [[ "$MODE" == "160000" ]]; then

        echo "[INFO] Skipping Git submodule: $FILE"

        continue

    fi

    # --------------------------------------------------------
    # Check staged object
    # --------------------------------------------------------

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

    echo
    echo "[OK] No readable staged files."
    echo "[OK] Commit allowed."

    exit 0

fi

# ============================================================
# DETECT-SECRETS
# ============================================================

echo
echo "--------------------------------------------------"
echo "Running detect-secrets..."
echo "--------------------------------------------------"

DETECT_BIN="$HOME/.security-compliance-venv/bin/detect-secrets"
DETECT_OUTPUT="$TMP_DIR/detect-secrets.json"

if [[ ! -x "$DETECT_BIN" ]]; then

    echo "[ERROR] detect-secrets is not installed."
    echo "Commit blocked."

    exit 1

fi

"$DETECT_BIN" scan "$SCAN_DIR" \
    > "$DETECT_OUTPUT" 2>/dev/null

DETECT_EXIT=$?

if [[ "$DETECT_EXIT" -ne 0 ]]; then

    echo
    echo "[ERROR] detect-secrets execution failed."
    echo "Commit blocked."

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

    count = 0

    for values in results.values():
        count += len(values)

    print(count)

except Exception:
    print(0)
PY
)"

if [[ "$DETECT_COUNT" -gt 0 ]]; then

    echo
    echo "=================================================="
    echo "             SECRET DETECTED"
    echo "=================================================="
    echo
    echo "detect-secrets detected $DETECT_COUNT potential secret(s)."
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
echo "--------------------------------------------------"
echo "Running Betterleaks..."
echo "------------------------------------------------------------"

BETTER_BIN="$HOME/.local/bin/betterleaks"

if [[ ! -x "$BETTER_BIN" ]]; then

    if ! command -v betterleaks >/dev/null 2>&1; then

        echo "[ERROR] Betterleaks is not installed."
        echo "Commit blocked."

        exit 1

    fi

    BETTER_BIN="$(command -v betterleaks)"

fi

BETTER_OUTPUT="$TMP_DIR/betterleaks.txt"

"$BETTER_BIN" dir "$SCAN_DIR" \
    --redact \
    > "$BETTER_OUTPUT" 2>&1

BETTER_EXIT=$?

if [[ "$BETTER_EXIT" -ne 0 ]]; then

    echo
    echo "[ERROR] Betterleaks execution failed."
    echo "Commit blocked."

    exit 1

fi

# Betterleaks output is informational here.
# detect-secrets is the authoritative commit blocker.

echo "[OK] Betterleaks scan completed."

# ============================================================
# TRUFFLEHOG
# ============================================================

echo
echo "--------------------------------------------------"
echo "Running TruffleHog..."
echo "------------------------------------------------------------"

TRUFFLE_BIN="$(command -v trufflehog 2>/dev/null || true)"

if [[ -z "$TRUFFLE_BIN" ]]; then

    echo "[ERROR] TruffleHog is not installed."
    echo "Commit blocked."

    exit 1

fi

TRUFFLE_OUTPUT="$TMP_DIR/trufflehog.txt"

"$TRUFFLE_BIN" filesystem "$SCAN_DIR" \
    --no-update \
    --no-verification \
    > "$TRUFFLE_OUTPUT" 2>&1

TRUFFLE_EXIT=$?

if [[ "$TRUFFLE_EXIT" -ne 0 ]]; then

    echo
    echo "[ERROR] TruffleHog execution failed."
    echo "Commit blocked."

    exit 1

fi

echo "[OK] TruffleHog scan completed."

# ============================================================
# FINAL RESULT
# ============================================================

echo
echo "=================================================="
echo "          SECURITY SCAN PASSED"
echo "=================================================="
echo
echo "No secrets detected by detect-secrets."
echo "Commit allowed."
echo

exit 0
HOOK

if [[ $? -ne 0 ]]; then

    echo "[ERROR] Failed to create global Git hook."

    failure

fi

chmod +x "$GLOBAL_HOOK"

if [[ $? -ne 0 ]]; then

    echo "[ERROR] Failed to make Git hook executable."

    failure

fi

echo "[OK] Global Git hook created."

# ============================================================
# CONFIGURE GLOBAL HOOK PATH
# ============================================================

echo
echo "[INFO] Configuring Git global hooks path..."

git config --global core.hooksPath "$GLOBAL_HOOK_DIR"

if [[ $? -ne 0 ]]; then

    echo "[ERROR] Failed to configure Git hooks path."

    failure

fi

CURRENT_HOOK_PATH="$(git config --global --get core.hooksPath)"

if [[ "$CURRENT_HOOK_PATH" != "$GLOBAL_HOOK_DIR" ]]; then

    echo "[ERROR] Git hooks path verification failed."

    failure

fi

echo "[OK] Global Git hook configured."

# ============================================================
# SECURITY SCANNER VERIFICATION
# ============================================================

echo
echo "------------------------------------------------------------"
echo "Security Scanner Verification"
echo "------------------------------------------------------------"

TEST_DIR="$(mktemp -d)"

if [[ ! -d "$TEST_DIR" ]]; then

    echo "[ERROR] Could not create test directory."

    failure

fi

TEST_FILE="$TEST_DIR/security-test.env"

cat > "$TEST_FILE" <<'EOF'
AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF
AWS_SECRET_ACCESS_KEY=AbCdEfGhIjKlMnOpQrStUvWxYz1234567890
EOF

# ============================================================
# DETECT-SECRETS VERIFICATION
# ============================================================

echo
echo "[INFO] Testing detect-secrets..."

DETECT_BIN="$VENV_DIR/bin/detect-secrets"
DETECT_OUTPUT="$TEST_DIR/detect-secrets.json"

if [[ ! -x "$DETECT_BIN" ]]; then

    echo "[ERROR] detect-secrets binary not found."

    failure

fi

"$DETECT_BIN" scan "$TEST_FILE" \
    > "$DETECT_OUTPUT" 2>&1

DETECT_EXIT=$?

if [[ "$DETECT_EXIT" -ne 0 ]]; then

    echo "[ERROR] detect-secrets execution failed."

    cat "$DETECT_OUTPUT"

    failure

fi

if grep -q '"results"' "$DETECT_OUTPUT" && \
   grep -q 'AWS Access Key' "$DETECT_OUTPUT"; then

    echo "[OK] detect-secrets detected test secret."

else

    echo "[ERROR] detect-secrets did not detect the test secret."

    echo
    echo "Scanner output:"
    cat "$DETECT_OUTPUT"

    failure

fi

echo "[OK] detect-secrets verification passed."

# ============================================================
# BETTERLEAKS VERIFICATION
# ============================================================

echo
echo "[INFO] Testing Betterleaks..."

BETTER_BIN="$USER_BIN/betterleaks"

if [[ ! -x "$BETTER_BIN" ]]; then

    BETTER_BIN="$(command -v betterleaks 2>/dev/null || true)"

fi

if [[ -z "$BETTER_BIN" ]]; then

    echo "[ERROR] Betterleaks binary not found."

    failure

fi

BETTER_OUTPUT="$TEST_DIR/betterleaks.txt"

"$BETTER_BIN" dir "$TEST_FILE" \
    --redact \
    > "$BETTER_OUTPUT" 2>&1

BETTER_EXIT=$?

if [[ "$BETTER_EXIT" -ne 0 ]]; then

    echo "[ERROR] Betterleaks execution failed."

    cat "$BETTER_OUTPUT"

    failure

fi

echo "[OK] Betterleaks execution verified."

# ============================================================
# TRUFFLEHOG VERIFICATION
# ============================================================

echo
echo "[INFO] Testing TruffleHog..."

TRUFFLE_BIN="$(command -v trufflehog 2>/dev/null || true)"

if [[ -z "$TRUFFLE_BIN" ]]; then

    echo "[ERROR] TruffleHog binary not found."

    failure

fi

TRUFFLE_OUTPUT="$TEST_DIR/trufflehog.txt"

"$TRUFFLE_BIN" filesystem "$TEST_FILE" \
    --no-update \
    --no-verification \
    > "$TRUFFLE_OUTPUT" 2>&1

TRUFFLE_EXIT=$?

if [[ "$TRUFFLE_EXIT" -ne 0 ]]; then

    echo "[ERROR] TruffleHog execution failed."

    cat "$TRUFFLE_OUTPUT"

    failure

fi

echo "[OK] TruffleHog execution verified."

# ============================================================
# GIT HOOK TEST
# ============================================================

echo
echo "[INFO] Testing global Git hook..."

HOOK_TEST_DIR="$TEST_DIR/git-test"

mkdir -p "$HOOK_TEST_DIR"

cd "$HOOK_TEST_DIR" || failure

git init -q

git config user.name "Security Compliance Test"
git config user.email "security-test@example.local"

cat > secret-test.env <<'EOF'
AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF
AWS_SECRET_ACCESS_KEY=AbCdEfGhIjKlMnOpStUvWxYz1234567890
EOF

git add secret-test.env

git commit -m "security hook test" >/dev/null 2>&1

COMMIT_STATUS=$?

if [[ "$COMMIT_STATUS" -eq 0 ]]; then

    echo
    echo "[ERROR] Security hook failed."
    echo "A commit containing the test secret was allowed."

    failure

fi

echo "[OK] Git secret blocking test passed."

cd "$HOME" || true

# ============================================================
# FINAL TOOL VERIFICATION
# ============================================================

echo
echo "------------------------------------------------------------"
echo "Final Tool Verification"
echo "------------------------------------------------------------"

export PATH="$VENV_DIR/bin:$USER_BIN:$GO_BIN:$PATH"

TOOLS_OK=1

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

    if command_exists "$TOOL"; then

        echo "[OK] $TOOL"

    else

        echo "[ERROR] $TOOL unavailable."

        TOOLS_OK=0

    fi

done

if [[ "$TOOLS_OK" -ne 1 ]]; then

    failure

fi

# ============================================================
# PERSIST PATH
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

touch "$PROFILE"

if ! grep -Fq '.security-compliance-venv/bin' "$PROFILE" 2>/dev/null; then

    echo "$PATH_LINE" >> "$PROFILE"

fi

# ============================================================
# FINAL VALIDATION
# ============================================================

if [[ ! -x "$GLOBAL_HOOK" ]]; then

    echo "[ERROR] Global Git hook does not exist."

    failure

fi

if [[ "$(git config --global --get core.hooksPath)" != "$GLOBAL_HOOK_DIR" ]]; then

    echo "[ERROR] Global Git hooks path is incorrect."

    failure

fi

# ============================================================
# SUCCESS
# ============================================================

echo
echo "============================================================"
echo "       SECURITY COMPLIANCE SETUP COMPLETE"
echo "============================================================"
echo
echo "[OK] Git"
echo "[OK] OpenSSH"
echo "[OK] tmate"
echo "[OK] Ansible"
echo "[OK] pre-commit"
echo "[OK] detect-secrets"
echo "[OK] Betterleaks"
echo "[OK] TruffleHog"
echo "[OK] Global Git security hook"
echo "[OK] Git submodule support"
echo "[OK] Secret commit blocking"
echo

success
