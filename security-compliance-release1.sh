#!/usr/bin/env bash

# ============================================================
# SECURITY COMPLIANCE INSTALLER
# Diagnostic / Testing Version
# ============================================================

set -o pipefail

LOG_FILE="/tmp/security-compliance-install.log"

# Start logging immediately
exec > >(tee -a "$LOG_FILE") 2>&1

echo
echo "============================================================"
echo " SECURITY COMPLIANCE INSTALLER"
echo "============================================================"
echo
echo "[INFO] Log file: $LOG_FILE"
echo "[INFO] Script started."
echo

# ============================================================
# ERROR HANDLER
# ============================================================

trap '
echo
echo "============================================================"
echo " ERROR DETECTED"
echo "============================================================"
echo
echo "[ERROR] Command: $BASH_COMMAND"
echo "[ERROR] Exit code: $?"
echo "[ERROR] Log file: $LOG_FILE"
echo
' ERR

# ============================================================
# DETECT OS
# ============================================================

echo "------------------------------------------------------------"
echo "Operating System"
echo "------------------------------------------------------------"

OS="$(uname -s)"
ARCH="$(uname -m)"

echo "[INFO] OS: $OS"
echo "[INFO] Architecture: $ARCH"
echo

# ============================================================
# BASIC COMMANDS
# ============================================================

echo "------------------------------------------------------------"
echo "Checking Basic Commands"
echo "------------------------------------------------------------"

command -v curl
command -v uname
command -v bash

echo
echo "[OK] Basic commands available."
echo

# ============================================================
# LINUX
# ============================================================

if [[ "$OS" == "Linux" ]]; then

    echo "------------------------------------------------------------"
    echo "Linux Detected"
    echo "------------------------------------------------------------"

    if command -v sudo >/dev/null 2>&1; then
        echo "[OK] sudo available."
    else
        echo "[ERROR] sudo not available."
        exit 1
    fi

    if command -v apt-get >/dev/null 2>&1; then

        echo "[INFO] Ubuntu/Debian detected."
        echo "[INFO] Updating package lists..."

        sudo apt-get update

        echo "[INFO] Installing required packages..."

        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
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

        echo "[OK] Linux packages installed."

    elif command -v dnf >/dev/null 2>&1; then

        echo "[INFO] Fedora/RHEL detected."

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

    elif command -v yum >/dev/null 2>&1; then

        echo "[INFO] Yum-based Linux detected."

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

    else

        echo "[ERROR] Unsupported Linux package manager."
        exit 1

    fi

# ============================================================
# MACOS
# ============================================================

elif [[ "$OS" == "Darwin" ]]; then

    echo "------------------------------------------------------------"
    echo "macOS Detected"
    echo "------------------------------------------------------------"

    if ! command -v brew >/dev/null 2>&1; then

        echo "[INFO] Homebrew not found."
        echo "[INFO] Installing Homebrew..."

        NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    fi

    if [[ -x "/opt/homebrew/bin/brew" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi

    if [[ -x "/usr/local/bin/brew" ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi

    echo "[INFO] Installing macOS dependencies..."

    brew install \
        git \
        openssh \
        tmate \
        python \
        jq \
        wget \
        go \
        betterleaks \
        trufflehog

else

    echo "[ERROR] Unsupported operating system."
    exit 1

fi

# ============================================================
# VERIFY SYSTEM TOOLS
# ============================================================

echo
echo "------------------------------------------------------------"
echo "System Tool Verification"
echo "------------------------------------------------------------"

for TOOL in git ssh tmate python3; do

    echo "[INFO] Checking $TOOL..."

    if command -v "$TOOL" >/dev/null 2>&1; then

        echo "[OK] $TOOL found:"
        command -v "$TOOL"

    else

        echo "[ERROR] $TOOL NOT FOUND."
        exit 1

    fi

done

# ============================================================
# PYTHON VENV
# ============================================================

echo
echo "------------------------------------------------------------"
echo "Python Environment"
echo "------------------------------------------------------------"

VENV="$HOME/.security-compliance-venv"

echo "[INFO] Creating Python environment: $VENV"

python3 -m venv "$VENV"

echo "[OK] Python virtual environment created."

# ============================================================
# PIP
# ============================================================

echo "[INFO] Upgrading pip..."

"$VENV/bin/python" -m pip install --upgrade pip

echo "[OK] pip ready."

# ============================================================
# ANSIBLE
# ============================================================

echo
echo "[INFO] Installing Ansible..."

"$VENV/bin/python" -m pip install ansible

echo "[OK] Ansible installed."

# ============================================================
# DETECT-SECRETS
# ============================================================

echo
echo "[INFO] Installing detect-secrets..."

"$VENV/bin/python" -m pip install detect-secrets

echo "[OK] detect-secrets installed."

# ============================================================
# PRE-COMMIT
# ============================================================

echo
echo "[INFO] Installing pre-commit..."

"$VENV/bin/python" -m pip install pre-commit

echo "[OK] pre-commit installed."

# ============================================================
# PATH
# ============================================================

export PATH="$VENV/bin:$HOME/.local/bin:$HOME/go/bin:$PATH"

mkdir -p "$HOME/.local/bin"

ln -sf "$VENV/bin/ansible" \
    "$HOME/.local/bin/ansible"

ln -sf "$VENV/bin/ansible-playbook" \
    "$HOME/.local/bin/ansible-playbook"

ln -sf "$VENV/bin/detect-secrets" \
    "$HOME/.local/bin/detect-secrets"

ln -sf "$VENV/bin/pre-commit" \
    "$HOME/.local/bin/pre-commit"

# ============================================================
# BETTERLEAKS - LINUX
# ============================================================

if [[ "$OS" == "Linux" ]]; then

    echo
    echo "------------------------------------------------------------"
    echo "Betterleaks"
    echo "------------------------------------------------------------"

    echo "[INFO] Checking Go..."

    if ! command -v go >/dev/null 2>&1; then

        echo "[ERROR] Go is not installed."
        exit 1

    fi

    echo "[OK] Go found:"
    go version

    export GOPATH="${GOPATH:-$HOME/go}"

    mkdir -p "$GOPATH/bin"

    export PATH="$GOPATH/bin:$PATH"

    echo
    echo "[INFO] Installing Betterleaks v1.7.2..."

    go install github.com/betterleaks/betterleaks@v1.7.2

    echo
    echo "[INFO] Checking Betterleaks binary..."

    if [[ -f "$GOPATH/bin/betterleaks" ]]; then

        chmod +x "$GOPATH/bin/betterleaks"

        ln -sf \
            "$GOPATH/bin/betterleaks" \
            "$HOME/.local/bin/betterleaks"

        echo "[OK] Betterleaks binary installed."

    else

        echo "[ERROR] Betterleaks binary was not created."
        exit 1

    fi

fi

# ============================================================
# TRUFFLEHOG - LINUX
# ============================================================

if [[ "$OS" == "Linux" ]]; then

    echo
    echo "------------------------------------------------------------"
    echo "TruffleHog"
    echo "------------------------------------------------------------"

    if command -v trufflehog >/dev/null 2>&1; then

        echo "[OK] TruffleHog already installed."

    else

        echo "[INFO] Installing TruffleHog..."

        curl -sSfL \
            https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh \
            | sudo sh -s -- -b /usr/local/bin

        echo "[OK] TruffleHog installation command completed."

    fi

fi

# ============================================================
# FINAL PATH
# ============================================================

export PATH="$HOME/.security-compliance-venv/bin:$HOME/.local/bin:$HOME/go/bin:$PATH"

echo
echo "============================================================"
echo " FINAL VERIFICATION"
echo "============================================================"

echo
echo "[1/9] Git"

git --version

echo
echo "[2/9] SSH"

ssh -V

echo
echo "[3/9] tmate"

tmate -V

echo
echo "[4/9] Ansible"

ansible --version | head -1

echo
echo "[5/9] detect-secrets"

detect-secrets --version

echo
echo "[6/9] pre-commit"

pre-commit --version

echo
echo "[7/9] Betterleaks"

betterleaks --version

echo
echo "[8/9] TruffleHog"

trufflehog --version

echo
echo "[9/9] Python"

python3 --version

# ============================================================
# SUCCESS
# ============================================================

echo
echo "============================================================"
echo " ALL COMPONENTS INSTALLED"
echo "============================================================"

echo
echo "[OK] Installation completed successfully."
echo

# Delete log ONLY after everything succeeds.
rm -f "$LOG_FILE"

echo "Installation completed successfully"

exit 0
