#!/usr/bin/env bash

# ============================================================
# SECURITY COMPLIANCE INSTALLER
# ============================================================
#
# Supported:
#   Ubuntu / Debian Linux
#   Fedora / RHEL Linux
#   macOS Intel
#   macOS Apple Silicon
#
# Installs:
#   1. Git
#   2. OpenSSH
#   3. tmate
#   4. Ansible
#   5. Betterleaks
#   6. TruffleHog
#   7. detect-secrets
#   8. pre-commit
#
# Behaviour:
#
#   During installation:
#       Installation logs are displayed.
#
#   SUCCESS:
#       Logs are deleted.
#       Only:
#       Installation completed successfully
#
#   FAILURE:
#       Logs are retained.
#       Failure message + log location are displayed.
#
# ============================================================

set -u

# ============================================================
# CONFIGURATION
# ============================================================

BETTERLEAKS_VERSION="v1.7.2"

VENV_DIR="$HOME/.security-compliance-venv"
USER_BIN="$HOME/.local/bin"

LOG_FILE="/tmp/security-compliance-install-$(date +%Y%m%d-%H%M%S).log"

TMP_DIR=""

# ============================================================
# LOGGING
# ============================================================

# Display logs AND save them to a file.
#
# tee ensures we can see the exact command that fails.
#
exec > >(tee -a "$LOG_FILE") 2>&1

echo "============================================================"
echo "        SECURITY COMPLIANCE INSTALLER"
echo "============================================================"
echo
echo "[INFO] Log file: $LOG_FILE"
echo

# ============================================================
# CLEANUP TEMPORARY FILES
# ============================================================

cleanup_temp()
{
    if [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]]; then
        rm -rf "$TMP_DIR" >/dev/null 2>&1 || true
    fi
}

trap cleanup_temp EXIT

# ============================================================
# SUCCESS
# ============================================================

success()
{
    cleanup_temp

    # Remove installation log after successful installation.
    rm -f "$LOG_FILE" >/dev/null 2>&1 || true

    echo
    echo "============================================================"
    echo "Installation completed successfully"
    echo "============================================================"

    exit 0
}

# ============================================================
# FAILURE
# ============================================================

failure()
{
    cleanup_temp

    echo
    echo "============================================================"
    echo "Installation failed"
    echo "============================================================"
    echo
    echo "Installation log retained at:"
    echo "$LOG_FILE"
    echo
    echo "Please share the last part of this log for troubleshooting."
    echo

    exit 1
}

fail()
{
    failure
}

# ============================================================
# DETECT OPERATING SYSTEM
# ============================================================

echo "[INFO] Detecting operating system..."

OS="$(uname -s 2>/dev/null)"

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
        fail
        ;;

esac

# ============================================================
# DETECT ARCHITECTURE
# ============================================================

ARCH_RAW="$(uname -m 2>/dev/null)"

case "$ARCH_RAW" in

    x86_64|amd64)
        ARCH="amd64"
        ;;

    arm64|aarch64)
        ARCH="arm64"
        ;;

    *)
        echo "[ERROR] Unsupported architecture: $ARCH_RAW"
        fail
        ;;

esac

echo "[INFO] Architecture: $ARCH"
echo

# ============================================================
# CREATE USER BIN
# ============================================================

echo "[INFO] Creating user binary directory..."

mkdir -p "$USER_BIN" || fail

echo "[OK] User binary directory ready."
echo

# ============================================================
# LINUX PACKAGE INSTALLATION
# ============================================================

install_linux_packages()
{
    echo "------------------------------------------------------------"
    echo "Linux Dependencies"
    echo "------------------------------------------------------------"

    if ! command -v sudo >/dev/null 2>&1; then

        echo "[ERROR] sudo is not installed."
        return 1

    fi

    echo "[INFO] sudo available."

    # --------------------------------------------------------
    # Ubuntu / Debian
    # --------------------------------------------------------

    if command -v apt-get >/dev/null 2>&1; then

        echo "[INFO] Debian/Ubuntu package manager detected."
        echo "[INFO] Updating package lists..."

        sudo apt-get update -qq

        if [[ $? -ne 0 ]]; then
            echo "[ERROR] apt-get update failed."
            return 1
        fi

        echo "[OK] Package lists updated."

        echo "[INFO] Installing required packages..."

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
            tar \
            gzip \
            build-essential \
            golang-go

        if [[ $? -ne 0 ]]; then
            echo "[ERROR] Required Linux packages could not be installed."
            return 1
        fi

        echo "[OK] Linux dependencies installed."

        return 0
    fi

    # --------------------------------------------------------
    # Fedora / RHEL
    # --------------------------------------------------------

    if command -v dnf >/dev/null 2>&1; then

        echo "[INFO] DNF package manager detected."

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
            tar \
            gzip \
            gcc \
            make \
            golang

        if [[ $? -ne 0 ]]; then
            echo "[ERROR] Required Linux packages could not be installed."
            return 1
        fi

        echo "[OK] Linux dependencies installed."

        return 0
    fi

    # --------------------------------------------------------
    # CentOS / older RHEL
    # --------------------------------------------------------

    if command -v yum >/dev/null 2>&1; then

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
            tar \
            gzip \
            gcc \
            make \
            golang

        if [[ $? -ne 0 ]]; then
            echo "[ERROR] Required Linux packages could not be installed."
            return 1
        fi

        echo "[OK] Linux dependencies installed."

        return 0
    fi

    echo "[ERROR] No supported Linux package manager found."

    return 1
}

# ============================================================
# macOS PACKAGE INSTALLATION
# ============================================================

install_macos_packages()
{
    echo "------------------------------------------------------------"
    echo "macOS Dependencies"
    echo "------------------------------------------------------------"

    # --------------------------------------------------------
    # Check Homebrew
    # --------------------------------------------------------

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

    # --------------------------------------------------------
    # Configure Homebrew PATH
    # --------------------------------------------------------

    if [[ -x "/opt/homebrew/bin/brew" ]]; then

        eval "$(/opt/homebrew/bin/brew shellenv)"

    elif [[ -x "/usr/local/bin/brew" ]]; then

        eval "$(/usr/local/bin/brew shellenv)"

    fi

    if ! command -v brew >/dev/null 2>&1; then

        echo "[ERROR] Homebrew could not be found after installation."
        return 1

    fi

    echo "[OK] Homebrew available."

    # --------------------------------------------------------
    # Update Homebrew
    # --------------------------------------------------------

    echo "[INFO] Updating Homebrew..."

    brew update

    if [[ $? -ne 0 ]]; then
        echo "[ERROR] Homebrew update failed."
        return 1
    fi

    # --------------------------------------------------------
    # Install packages
    # --------------------------------------------------------

    echo "[INFO] Installing macOS dependencies..."

    brew install \
        git \
        openssh \
        tmate \
        python \
        wget \
        jq \
        go

    if [[ $? -ne 0 ]]; then
        echo "[ERROR] macOS dependencies could not be installed."
        return 1
    fi

    echo "[OK] macOS dependencies installed."

    return 0
}

# ============================================================
# INSTALL OS DEPENDENCIES
# ============================================================

if [[ "$PLATFORM" == "linux" ]]; then

    install_linux_packages || fail

else

    install_macos_packages || fail

fi

echo

# ============================================================
# VERIFY BASIC TOOLS
# ============================================================

echo "------------------------------------------------------------"
echo "Verifying System Tools"
echo "------------------------------------------------------------"

for TOOL in curl git ssh tmate python3; do

    if command -v "$TOOL" >/dev/null 2>&1; then

        echo "[OK] $TOOL found."

    else

        echo "[ERROR] $TOOL not found."
        fail

    fi

done

# ============================================================
# PYTHON VIRTUAL ENVIRONMENT
# ============================================================

echo
echo "------------------------------------------------------------"
echo "Python Security Tools"
echo "------------------------------------------------------------"

echo "[INFO] Python: $PYTHON"

if [[ ! -d "$VENV_DIR" ]]; then

    echo "[INFO] Creating Python virtual environment..."

    python3 -m venv "$VENV_DIR"

    if [[ $? -ne 0 ]]; then
        echo "[ERROR] Python virtual environment creation failed."
        fail
    fi

else

    echo "[OK] Existing virtual environment found."

fi

# ============================================================
# PIP
# ============================================================

echo "[INFO] Upgrading pip..."

"$VENV_DIR/bin/python" \
    -m pip install --upgrade pip

if [[ $? -ne 0 ]]; then

    echo "[ERROR] pip upgrade failed."
    fail

fi

echo "[OK] pip ready."

# ============================================================
# ANSIBLE
# ============================================================

echo
echo "[INFO] Installing Ansible..."

"$VENV_DIR/bin/python" \
    -m pip install ansible

if [[ $? -ne 0 ]]; then

    echo "[ERROR] Ansible installation failed."
    fail

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
    fail

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
    fail

fi

echo "[OK] pre-commit installed."

# ============================================================
# CREATE PYTHON TOOL LINKS
# ============================================================

echo
echo "[INFO] Creating Python tool links..."

ln -sf \
    "$VENV_DIR/bin/ansible" \
    "$USER_BIN/ansible"

ln -sf \
    "$VENV_DIR/bin/ansible-playbook" \
    "$USER_BIN/ansible-playbook"

ln -sf \
    "$VENV_DIR/bin/detect-secrets" \
    "$USER_BIN/detect-secrets"

ln -sf \
    "$VENV_DIR/bin/pre-commit" \
    "$USER_BIN/pre-commit"

echo "[OK] Python tool links created."

# ============================================================
# PATH
# ============================================================

export PATH="$VENV_DIR/bin:$USER_BIN:$HOME/go/bin:$PATH"

# ============================================================
# BETTERLEAKS
# ============================================================

echo
echo "------------------------------------------------------------"
echo "Betterleaks"
echo "------------------------------------------------------------"

install_betterleaks()
{
    # --------------------------------------------------------
    # macOS
    # --------------------------------------------------------

    if [[ "$PLATFORM" == "macos" ]]; then

        echo "[INFO] Installing Betterleaks using Homebrew..."

        brew install betterleaks

        if [[ $? -ne 0 ]]; then

            echo "[ERROR] Betterleaks installation failed."

            return 1

        fi

        return 0

    fi

    # --------------------------------------------------------
    # Linux
    # --------------------------------------------------------

    echo "[INFO] Checking Go..."

    if ! command -v go >/dev/null 2>&1; then

        echo "[ERROR] Go was not found."
        return 1

    fi

    echo "[OK] Go found: $(go version)"

    export GOPATH="${GOPATH:-$HOME/go}"

    mkdir -p "$GOPATH/bin"

    export PATH="$GOPATH/bin:$PATH"

    echo "[INFO] Installing Betterleaks $BETTERLEAKS_VERSION..."

    go install \
        "github.com/betterleaks/betterleaks@${BETTERLEAKS_VERSION}"

    if [[ $? -ne 0 ]]; then

        echo "[ERROR] Betterleaks Go installation failed."
        return 1

    fi

    if [[ ! -f "$GOPATH/bin/betterleaks" ]]; then

        echo "[ERROR] Betterleaks binary was not created."
        return 1

    fi

    chmod +x "$GOPATH/bin/betterleaks"

    ln -sf \
        "$GOPATH/bin/betterleaks" \
        "$USER_BIN/betterleaks"

    if [[ $? -ne 0 ]]; then

        echo "[ERROR] Could not create Betterleaks link."
        return 1

    fi

    return 0
}

install_betterleaks || fail

echo "[OK] Betterleaks installed."

# ============================================================
# TRUFFLEHOG
# ============================================================

echo
echo "------------------------------------------------------------"
echo "TruffleHog"
echo "------------------------------------------------------------"

install_trufflehog()
{
    # --------------------------------------------------------
    # macOS
    # --------------------------------------------------------

    if [[ "$PLATFORM" == "macos" ]]; then

        echo "[INFO] Installing TruffleHog using Homebrew..."

        brew install trufflehog

        if [[ $? -ne 0 ]]; then

            echo "[ERROR] TruffleHog installation failed."

            return 1

        fi

        return 0
    fi

    # --------------------------------------------------------
    # Linux
    # --------------------------------------------------------

    if command -v trufflehog >/dev/null 2>&1; then

        echo "[OK] TruffleHog already installed."

        return 0

    fi

    echo "[INFO] Installing TruffleHog..."

    curl -fsSL \
        https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh \
        | sudo sh -s -- -b /usr/local/bin

    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then

        echo "[ERROR] TruffleHog installation failed."

        return 1

    fi

    return 0
}

install_trufflehog || fail

echo "[OK] TruffleHog installed."

# ============================================================
# VERIFY ALL TOOLS
# ============================================================

echo
echo "============================================================"
echo "Verifying Installation"
echo "============================================================"

export PATH="$VENV_DIR/bin:$USER_BIN:$HOME/go/bin:$PATH"

TOOLS=(
    git
    ssh
    tmate
    ansible
    ansible-playbook
    detect-secrets
    pre-commit
    betterleaks
    trufflehog
)

for TOOL in "${TOOLS[@]}"; do

    if command -v "$TOOL" >/dev/null 2>&1; then

        echo "[OK] $TOOL installed."

    else

        echo "[ERROR] $TOOL is missing."
        fail

    fi

done

# ============================================================
# DISPLAY VERSIONS
# ============================================================

echo
echo "------------------------------------------------------------"
echo "Installed Versions"
echo "------------------------------------------------------------"

git --version || true

python3 --version || true

ansible --version | head -1 || true

detect-secrets --version || true

pre-commit --version || true

betterleaks --version || true

trufflehog --version || true

tmate -V || true

# ============================================================
# PERMANENT PATH CONFIGURATION
# ============================================================

echo
echo "------------------------------------------------------------"
echo "Shell Configuration"
echo "------------------------------------------------------------"

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

    if [[ $? -ne 0 ]]; then

        echo "[ERROR] Could not update shell PATH."
        fail

    fi

    echo "[OK] PATH updated."

else

    echo "[OK] PATH already configured."

fi

# ============================================================
# FINAL CHECKS
# ============================================================

echo
echo "------------------------------------------------------------"
echo "Final Checks"
echo "------------------------------------------------------------"

"$VENV_DIR/bin/ansible" \
    --version \
    >/dev/null 2>&1 || fail

"$VENV_DIR/bin/detect-secrets" \
    --version \
    >/dev/null 2>&1 || fail

"$VENV_DIR/bin/pre-commit" \
    --version \
    >/dev/null 2>&1 || fail

betterleaks \
    --version \
    >/dev/null 2>&1 || fail

trufflehog \
    --version \
    >/dev/null 2>&1 || fail

tmate \
    -V \
    >/dev/null 2>&1 || fail

echo "[OK] All security tools verified."

# ============================================================
# SUCCESS
# ============================================================

success
