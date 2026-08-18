#!/usr/bin/env bash

# ============================================================
# SECURITY COMPLIANCE INSTALLER
# ============================================================
#
# Supported:
#   - Ubuntu / Debian Linux
#   - Fedora / RHEL / CentOS Linux
#   - macOS Intel
#   - macOS Apple Silicon
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
#   - Secret scanning on git commit
#
# Scanners:
#   - detect-secrets
#   - Betterleaks
#   - TruffleHog
#
# Behaviour:
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
GLOBAL_HOOK_DIR="$HOME/.git-hooks"
GLOBAL_HOOK="$GLOBAL_HOOK_DIR/pre-commit"

BETTERLEAKS_VERSION="v1.7.2"

LOG_FILE="/tmp/security-compliance-install-$(date +%Y%m%d-%H%M%S).log"

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
# TEMP DIRECTORY
# ============================================================

TMP_DIR=""

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
# LINUX DEPENDENCIES
# ============================================================

install_linux_dependencies()
{
    echo
    echo "------------------------------------------------------------"
    echo "Linux Dependencies"
    echo "------------------------------------------------------------"

    if ! command -v sudo >/dev/null 2>&1; then

        echo "[ERROR] sudo is required."

        return 1

    fi

    if command -v apt-get >/dev/null 2>&1; then

        echo "[INFO] Debian/Ubuntu detected."

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

        if [[ $? -ne 0 ]]; then
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
            return 1
        fi

        return 0

    fi

    echo "[ERROR] Unsupported Linux package manager."

    return 1
}

# ============================================================
# MACOS DEPENDENCIES
# ============================================================

install_macos_dependencies()
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
        return 1
    fi

    return 0
}

# ============================================================
# INSTALL OS DEPENDENCIES
# ============================================================

if [[ "$PLATFORM" == "linux" ]]; then

    install_linux_dependencies || failure

else

    install_macos_dependencies || failure

fi

# ============================================================
# VERIFY BASIC COMMANDS
# ============================================================

echo
echo "------------------------------------------------------------"
echo "Basic Tool Verification"
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
# PYTHON ENVIRONMENT
# ============================================================

echo
echo "------------------------------------------------------------"
echo "Python Security Environment"
echo "------------------------------------------------------------"

if [[ ! -d "$VENV_DIR" ]]; then

    python3 -m venv "$VENV_DIR"

    if [[ $? -ne 0 ]]; then

        echo "[ERROR] Could not create Python virtual environment."

        failure

    fi

fi

export PATH="$VENV_DIR/bin:$USER_BIN:$HOME/go/bin:$PATH"

"$VENV_DIR/bin/python" -m pip install --upgrade pip \
    >/dev/null 2>&1

if [[ $? -ne 0 ]]; then

    echo "[ERROR] pip setup failed."

    failure

fi

# ============================================================
# ANSIBLE
# ============================================================

echo
echo "[INFO] Installing Ansible..."

"$VENV_DIR/bin/python" -m pip install ansible

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

"$VENV_DIR/bin/python" -m pip install detect-secrets

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

"$VENV_DIR/bin/python" -m pip install pre-commit

if [[ $? -ne 0 ]]; then

    echo "[ERROR] pre-commit installation failed."

    failure

fi

echo "[OK] pre-commit installed."

# ============================================================
# USER BIN LINKS
# ============================================================

ln -sf "$VENV_DIR/bin/ansible" "$USER_BIN/ansible"
ln -sf "$VENV_DIR/bin/ansible-playbook" "$USER_BIN/ansible-playbook"
ln -sf "$VENV_DIR/bin/detect-secrets" "$USER_BIN/detect-secrets"
ln -sf "$VENV_DIR/bin/pre-commit" "$USER_BIN/pre-commit"

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

        echo "[ERROR] Go is unavailable."

        failure

    fi

    export GOPATH="${GOPATH:-$HOME/go}"

    mkdir -p "$GOPATH/bin"

    export PATH="$GOPATH/bin:$PATH"

    echo "[INFO] Installing Betterleaks..."

    go install \
        "github.com/betterleaks/betterleaks@${BETTERLEAKS_VERSION}"

    if [[ $? -ne 0 ]]; then

        echo "[ERROR] Betterleaks installation failed."

        failure

    fi

    if [[ ! -x "$GOPATH/bin/betterleaks" ]]; then

        echo "[ERROR] Betterleaks binary was not created."

        failure

    fi

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

if ! command -v trufflehog >/dev/null 2>&1; then

    echo "[ERROR] TruffleHog command unavailable."

    failure

fi

echo "[OK] TruffleHog installed."

# ============================================================
# GLOBAL GIT PRE-COMMIT HOOK
# ============================================================

echo
echo "------------------------------------------------------------"
echo "Global Git Security Hook"
echo "------------------------------------------------------------"

cat > "$GLOBAL_HOOK" <<'HOOK'
#!/usr/bin/env bash

# ============================================================
# GLOBAL SECURITY PRE-COMMIT HOOK
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

STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACMR)

if [[ -z "$STAGED_FILES" ]]; then

    echo "[OK] No staged files."
    exit 0

fi

FOUND_FILES=0

while IFS= read -r FILE
do

    [[ -z "$FILE" ]] && continue

    # --------------------------------------------------------
    # Skip Git submodules
    # --------------------------------------------------------

    MODE=$(git ls-files -s -- "$FILE" 2>/dev/null | awk '{print $1}')

    if [[ "$MODE" == "160000" ]]; then

        echo "[INFO] Git submodule skipped: $FILE"

        continue

    fi

    # --------------------------------------------------------
    # Check staged object
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
echo "--------------------------------------------------"
echo "Running detect-secrets..."
echo "--------------------------------------------------"

DETECT_OUTPUT="$TMP_DIR/detect-secrets.json"

if ! detect-secrets scan "$SCAN_DIR" \
    > "$DETECT_OUTPUT" 2>/dev/null; then

    echo
    echo "[ERROR] detect-secrets failed to execute."
    echo "Commit blocked."

    exit 1

fi

DETECT_COUNT=$(python3 - "$DETECT_OUTPUT" <<'PY'
import json
import sys

try:
    with open(sys.argv[1]) as f:
        data = json.load(f)

    count = sum(
        len(values)
        for values in data.get("results", {}).values()
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
echo "--------------------------------------------------"
echo "Running Betterleaks..."
echo "--------------------------------------------------"

BETTER_OUTPUT="$TMP_DIR/betterleaks.txt"

betterleaks dir "$SCAN_DIR" \
    --redact \
    > "$BETTER_OUTPUT" 2>&1

BETTER_STATUS=$?

if [[ "$BETTER_STATUS" -ne 0 ]]; then

    echo
    echo "[ERROR] Betterleaks failed to execute."
    echo "Commit blocked."

    exit 1

fi

if grep -qiE \
    "leak found|leaks found|secret found|finding|detected" \
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
echo "--------------------------------------------------"
echo "Running TruffleHog..."
echo "--------------------------------------------------"

TRUFFLE_OUTPUT="$TMP_DIR/trufflehog.txt"

trufflehog filesystem "$SCAN_DIR" \
    --no-update \
    --no-verification \
    > "$TRUFFLE_OUTPUT" 2>&1

TRUFFLE_STATUS=$?

if [[ "$TRUFFLE_STATUS" -ne 0 ]]; then

    echo
    echo "[ERROR] TruffleHog failed to execute."
    echo "Commit blocked."

    exit 1

fi

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
# CONFIGURE GLOBAL GIT HOOK
# ============================================================

echo
echo "[INFO] Configuring Git global hooks path..."

git config --global core.hooksPath "$GLOBAL_HOOK_DIR"

if [[ $? -ne 0 ]]; then

    echo "[ERROR] Could not configure Git hooks path."

    failure

fi

HOOK_PATH="$(git config --global --get core.hooksPath)"

if [[ "$HOOK_PATH" != "$GLOBAL_HOOK_DIR" ]]; then

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

TMP_DIR="$(mktemp -d)"

if [[ ! -d "$TMP_DIR" ]]; then

    echo "[ERROR] Could not create temporary directory."

    failure

fi

TEST_FILE="$TMP_DIR/security-test.env"

cat > "$TEST_FILE" <<'EOF'
AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF
AWS_SECRET_ACCESS_KEY=AbCdEfGhIjKlMnOpQrStUvWxYz1234567890
EOF

# ============================================================
# DETECT-SECRETS VERIFICATION
# ============================================================

echo
echo "[INFO] Testing detect-secrets..."

DETECT_TEST_OUTPUT="$TMP_DIR/detect-secrets.json"

"$VENV_DIR/bin/detect-secrets" scan "$TEST_FILE" \
    > "$DETECT_TEST_OUTPUT" 2>&1

DETECT_STATUS=$?

if [[ "$DETECT_STATUS" -ne 0 ]]; then

    echo "[ERROR] detect-secrets execution failed."

    cat "$DETECT_TEST_OUTPUT"

    failure

fi

if grep -q "AWS Access Key" "$DETECT_TEST_OUTPUT"; then

    echo "[OK] detect-secrets verification passed."

else

    echo "[ERROR] detect-secrets did not detect the test secret."

    echo
    echo "detect-secrets output:"
    cat "$DETECT_TEST_OUTPUT"

    failure

fi

# ============================================================
# BETTERLEAKS VERIFICATION
# ============================================================

echo
echo "[INFO] Testing Betterleaks..."

BETTER_TEST_OUTPUT="$TMP_DIR/betterleaks.txt"

betterleaks dir "$TEST_FILE" \
    --redact \
    > "$BETTER_TEST_OUTPUT" 2>&1

BETTER_STATUS=$?

if [[ "$BETTER_STATUS" -ne 0 ]]; then

    echo "[ERROR] Betterleaks execution failed."

    cat "$BETTER_TEST_OUTPUT"

    failure

fi

echo "[OK] Betterleaks execution verified."

# ============================================================
# TRUFFLEHOG VERIFICATION
# ============================================================

echo
echo "[INFO] Testing TruffleHog..."

TRUFFLE_TEST_OUTPUT="$TMP_DIR/trufflehog.txt"

trufflehog filesystem "$TEST_FILE" \
    --no-update \
    --no-verification \
    > "$TRUFFLE_TEST_OUTPUT" 2>&1

TRUFFLE_STATUS=$?

if [[ "$TRUFFLE_STATUS" -ne 0 ]]; then

    echo "[ERROR] TruffleHog execution failed."

    cat "$TRUFFLE_TEST_OUTPUT"

    failure

fi

echo "[OK] TruffleHog execution verified."

# ============================================================
# FINAL COMMAND VERIFICATION
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

        echo "[ERROR] $TOOL is unavailable."

        failure

    fi

done

# ============================================================
# ADD USER PATH
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

if [[ ! -f "$PROFILE" ]]; then

    touch "$PROFILE"

fi

if ! grep -Fq '.security-compliance-venv/bin' "$PROFILE" 2>/dev/null; then

    echo "$PATH_LINE" >> "$PROFILE"

fi

# ============================================================
# FINAL CHECK
# ============================================================

if [[ ! -x "$GLOBAL_HOOK" ]]; then

    echo "[ERROR] Global Git hook is not executable."

    failure

fi

if [[ "$(git config --global --get core.hooksPath)" != "$GLOBAL_HOOK_DIR" ]]; then

    echo "[ERROR] Global Git hook configuration is incorrect."

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
echo "[OK] Git installed."
echo "[OK] OpenSSH installed."
echo "[OK] tmate installed."
echo "[OK] Ansible installed."
echo "[OK] pre-commit installed."
echo "[OK] detect-secrets installed."
echo "[OK] Betterleaks installed."
echo "[OK] TruffleHog installed."
echo "[OK] Global Git security hook installed."
echo "[OK] Git submodule handling enabled."
echo "[OK] Commit blocking enabled."
echo

success
