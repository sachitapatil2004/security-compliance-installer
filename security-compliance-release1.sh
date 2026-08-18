#!/usr/bin/env bash

# ============================================================
# COMPLETE SECURITY COMPLIANCE INSTALLER
# ============================================================
#
# Supported:
#   Linux
#   macOS
#
# Installs:
#   Git
#   OpenSSH
#   tmate
#   Ansible
#   pre-commit
#   detect-secrets
#   Betterleaks
#   TruffleHog
#
# Configures:
#   Global Git security pre-commit hook
#
# Installation output:
#   SUCCESS -> Installation completed successfully
#   FAILURE -> Installation failed
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
# SILENT LOGGING
# ============================================================

exec >"$LOG_FILE" 2>&1

# ============================================================
# FUNCTIONS
# ============================================================

cleanup()
{
    if [[ -n "${TEST_DIR:-}" && -d "${TEST_DIR:-}" ]]; then
        rm -rf "$TEST_DIR" >/dev/null 2>&1 || true
    fi
}

failure()
{
    cleanup

    echo "Installation failed"

    exit 1
}

success()
{
    cleanup

    rm -f "$LOG_FILE" >/dev/null 2>&1 || true

    echo "Installation completed successfully"

    exit 0
}

command_exists()
{
    command -v "$1" >/dev/null 2>&1
}

# ============================================================
# OS DETECTION
# ============================================================

OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in

    Linux)
        PLATFORM="linux"
        ;;

    Darwin)
        PLATFORM="macos"
        ;;

    *)
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
        failure
        ;;

esac

# ============================================================
# CREATE DIRECTORIES
# ============================================================

mkdir -p "$USER_BIN" || failure
mkdir -p "$GO_BIN" || failure
mkdir -p "$GLOBAL_HOOK_DIR" || failure

# ============================================================
# LINUX INSTALLATION
# ============================================================

install_linux()
{
    if ! command_exists sudo; then
        return 1
    fi

    # --------------------------------------------------------
    # Ubuntu / Debian
    # --------------------------------------------------------

    if command_exists apt-get; then

        sudo apt-get update -qq >/dev/null 2>&1

        if [[ $? -ne 0 ]]; then
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
            build-essential \
            >/dev/null 2>&1

        return $?

    fi

    # --------------------------------------------------------
    # Fedora
    # --------------------------------------------------------

    if command_exists dnf; then

        sudo dnf install -y -q \
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
            make \
            >/dev/null 2>&1

        return $?

    fi

    # --------------------------------------------------------
    # RHEL / CentOS
    # --------------------------------------------------------

    if command_exists yum; then

        sudo yum install -y -q \
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
            make \
            >/dev/null 2>&1

        return $?

    fi

    return 1
}

# ============================================================
# MACOS INSTALLATION
# ============================================================

install_macos()
{
    # --------------------------------------------------------
    # Homebrew
    # --------------------------------------------------------

    if ! command_exists brew; then

        NONINTERACTIVE=1 \
        /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
        >/dev/null 2>&1

        if [[ $? -ne 0 ]]; then
            return 1
        fi

    fi

    if [[ -x "/opt/homebrew/bin/brew" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)" \
            >/dev/null 2>&1
    fi

    if [[ -x "/usr/local/bin/brew" ]]; then
        eval "$(/usr/local/bin/brew shellenv)" \
            >/dev/null 2>&1
    fi

    if ! command_exists brew; then
        return 1
    fi

    brew update >/dev/null 2>&1

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
        go \
        >/dev/null 2>&1

    return $?
}

# ============================================================
# INSTALL SYSTEM DEPENDENCIES
# ============================================================

if [[ "$PLATFORM" == "linux" ]]; then

    install_linux >/dev/null 2>&1

    if [[ $? -ne 0 ]]; then
        failure
    fi

else

    install_macos >/dev/null 2>&1

    if [[ $? -ne 0 ]]; then
        failure
    fi

fi

# ============================================================
# PYTHON ENVIRONMENT
# ============================================================

if [[ ! -d "$VENV_DIR" ]]; then

    python3 -m venv "$VENV_DIR" \
        >/dev/null 2>&1

    if [[ $? -ne 0 ]]; then
        failure
    fi

fi

PYTHON="$VENV_DIR/bin/python"
PIP="$VENV_DIR/bin/pip"

if [[ ! -x "$PYTHON" ]]; then
    failure
fi

"$PYTHON" -m pip install --upgrade pip \
    >/dev/null 2>&1

if [[ $? -ne 0 ]]; then
    failure
fi

# ============================================================
# ANSIBLE
# ============================================================

"$PIP" install ansible \
    >/dev/null 2>&1

if [[ $? -ne 0 ]]; then
    failure
fi

ln -sf "$VENV_DIR/bin/ansible" \
    "$USER_BIN/ansible" \
    >/dev/null 2>&1

ln -sf "$VENV_DIR/bin/ansible-playbook" \
    "$USER_BIN/ansible-playbook" \
    >/dev/null 2>&1

if [[ ! -x "$VENV_DIR/bin/ansible" ]]; then
    failure
fi

# ============================================================
# PRE-COMMIT
# ============================================================

"$PIP" install pre-commit \
    >/dev/null 2>&1

if [[ $? -ne 0 ]]; then
    failure
fi

ln -sf "$VENV_DIR/bin/pre-commit" \
    "$USER_BIN/pre-commit" \
    >/dev/null 2>&1

if [[ ! -x "$VENV_DIR/bin/pre-commit" ]]; then
    failure
fi

# ============================================================
# DETECT-SECRETS
# ============================================================

"$PIP" install detect-secrets \
    >/dev/null 2>&1

if [[ $? -ne 0 ]]; then
    failure
fi

ln -sf "$VENV_DIR/bin/detect-secrets" \
    "$USER_BIN/detect-secrets" \
    >/dev/null 2>&1

if [[ ! -x "$VENV_DIR/bin/detect-secrets" ]]; then
    failure
fi

if ! "$VENV_DIR/bin/detect-secrets" --version \
    >/dev/null 2>&1; then
    failure
fi

# ============================================================
# BETTERLEAKS
# ============================================================

export PATH="$GO_BIN:$USER_BIN:$VENV_DIR/bin:$PATH"

if [[ "$PLATFORM" == "macos" ]]; then

    brew install betterleaks \
        >/dev/null 2>&1

    if [[ $? -ne 0 ]]; then
        failure
    fi

else

    if ! command_exists go; then
        failure
    fi

    go install \
        "github.com/betterleaks/betterleaks@${BETTERLEAKS_VERSION}" \
        >/dev/null 2>&1

    if [[ $? -ne 0 ]]; then
        failure
    fi

    if [[ ! -x "$GO_BIN/betterleaks" ]]; then
        failure
    fi

    ln -sf "$GO_BIN/betterleaks" \
        "$USER_BIN/betterleaks" \
        >/dev/null 2>&1

fi

BETTER_BIN="$USER_BIN/betterleaks"

if [[ ! -x "$BETTER_BIN" ]]; then

    BETTER_BIN="$(command -v betterleaks 2>/dev/null || true)"

fi

if [[ -z "$BETTER_BIN" ]]; then
    failure
fi

if ! "$BETTER_BIN" --help \
    >/dev/null 2>&1; then
    failure
fi

# ============================================================
# TRUFFLEHOG
# ============================================================

export PATH="$USER_BIN:$VENV_DIR/bin:$GO_BIN:$PATH"

if command_exists trufflehog; then

    :

else

    if [[ "$PLATFORM" == "macos" ]]; then

        brew install trufflehog \
            >/dev/null 2>&1

        if [[ $? -ne 0 ]]; then
            failure
        fi

    else

        curl -sSfL \
            https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh \
            | sudo sh -s -- -b /usr/local/bin \
            >/dev/null 2>&1

        if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
            failure
        fi

    fi

fi

if ! command_exists trufflehog; then
    failure
fi

if ! trufflehog --help \
    >/dev/null 2>&1; then
    failure
fi

# ============================================================
# GLOBAL GIT SECURITY HOOK
# ============================================================

cat > "$GLOBAL_HOOK" <<'HOOK'
#!/usr/bin/env bash

# ============================================================
# GLOBAL GIT SECURITY PRE-COMMIT HOOK
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
    exit 0
fi

READABLE_FILES=0

# ============================================================
# EXTRACT STAGED FILES
# ============================================================

while IFS= read -r FILE
do

    [[ -z "$FILE" ]] && continue

    MODE="$(git ls-files -s -- "$FILE" 2>/dev/null | awk '{print $1}')"

    # Git submodule
    if [[ "$MODE" == "160000" ]]; then
        continue
    fi

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
# DETECT-SECRETS
# ============================================================

echo
echo "Running detect-secrets..."

DETECT_BIN="$HOME/.security-compliance-venv/bin/detect-secrets"

if [[ ! -x "$DETECT_BIN" ]]; then

    echo
    echo "ERROR: detect-secrets is not installed."
    echo "COMMIT BLOCKED."

    exit 1

fi

DETECT_OUTPUT="$TMP_DIR/detect-secrets.json"

"$DETECT_BIN" scan "$SCAN_DIR" \
    > "$DETECT_OUTPUT" 2>/dev/null

if [[ $? -ne 0 ]]; then

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

    count = sum(len(values) for values in results.values())

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
    echo "detect-secrets detected potential secret(s)."
    echo
    echo "COMMIT BLOCKED."
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
echo "Running Betterleaks..."

BETTER_BIN="$HOME/.local/bin/betterleaks"

if [[ ! -x "$BETTER_BIN" ]]; then

    BETTER_BIN="$(command -v betterleaks 2>/dev/null || true)"

fi

if [[ -z "$BETTER_BIN" ]]; then

    echo
    echo "ERROR: Betterleaks is not installed."
    echo "COMMIT BLOCKED."

    exit 1

fi

"$BETTER_BIN" dir "$SCAN_DIR" \
    --redact \
    >/dev/null 2>&1

BETTER_EXIT=$?

if [[ "$BETTER_EXIT" -ne 0 ]]; then

    echo
    echo "ERROR: Betterleaks detected a problem."
    echo "COMMIT BLOCKED."

    exit 1

fi

echo "[OK] Betterleaks passed."

# ============================================================
# TRUFFLEHOG
# ============================================================

echo
echo "Running TruffleHog..."

TRUFFLE_BIN="$(command -v trufflehog 2>/dev/null || true)"

if [[ -z "$TRUFFLE_BIN" ]]; then

    echo
    echo "ERROR: TruffleHog is not installed."
    echo "COMMIT BLOCKED."

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
    echo "ERROR: TruffleHog detected a problem."
    echo "COMMIT BLOCKED."

    exit 1

fi

echo "[OK] TruffleHog passed."

# ============================================================
# FINAL RESULT
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

if [[ $? -ne 0 ]]; then
    failure
fi

chmod +x "$GLOBAL_HOOK" \
    >/dev/null 2>&1

if [[ $? -ne 0 ]]; then
    failure
fi

# ============================================================
# CONFIGURE GLOBAL GIT HOOK
# ============================================================

git config --global core.hooksPath "$GLOBAL_HOOK_DIR" \
    >/dev/null 2>&1

if [[ $? -ne 0 ]]; then
    failure
fi

CURRENT_HOOK_PATH="$(
    git config --global --get core.hooksPath \
    2>/dev/null
)"

if [[ "$CURRENT_HOOK_PATH" != "$GLOBAL_HOOK_DIR" ]]; then
    failure
fi

# ============================================================
# VERIFY TOOLS
# ============================================================

export PATH="$VENV_DIR/bin:$USER_BIN:$GO_BIN:$PATH"

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

    if ! command_exists "$TOOL"; then
        failure
    fi

done

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

touch "$PROFILE" \
    >/dev/null 2>&1

PATH_LINE='export PATH="$HOME/.security-compliance-venv/bin:$HOME/.local/bin:$HOME/go/bin:$PATH"'

if ! grep -Fq '.security-compliance-venv/bin' "$PROFILE" \
    2>/dev/null; then

    echo "$PATH_LINE" >> "$PROFILE"

fi

# ============================================================
# FINAL VERIFICATION
# ============================================================

if [[ ! -x "$GLOBAL_HOOK" ]]; then
    failure
fi

if [[ "$(git config --global --get core.hooksPath 2>/dev/null)" != "$GLOBAL_HOOK_DIR" ]]; then
    failure
fi

# ============================================================
# SUCCESS
# ============================================================

success
