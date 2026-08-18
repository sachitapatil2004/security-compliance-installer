#!/usr/bin/env bash

# ============================================================
# Silent Developer Security Tools Installer
#
# Supported:
#   - Ubuntu / Debian Linux
#   - macOS
#
# Installs:
#   - Betterleaks
#   - TruffleHog
#   - detect-secrets
#   - pre-commit
#   - Ansible
#   - tmate
#   - OpenSSH
#   - Git
#
# Output:
#   SUCCESS -> Installation completed successfully
#   FAILURE -> Installation failed
#
# All installation output is suppressed.
# ============================================================

set -u

# ------------------------------------------------------------
# Global configuration
# ------------------------------------------------------------

INSTALL_DIR="/usr/local/bin"
BETTERLEAKS_VERSION="v1.7.2"

# ------------------------------------------------------------
# Redirect all command output
# ------------------------------------------------------------

exec >/dev/null 2>&1

# ------------------------------------------------------------
# Failure handler
# ------------------------------------------------------------

fail()
{
    exec >/dev/tty 2>&1 2>/dev/null || true
    echo "Installation failed"
    exit 1
}

trap 'fail' ERR

# ------------------------------------------------------------
# Restore terminal output
# ------------------------------------------------------------

success()
{
    exec >/dev/tty 2>&1 2>/dev/null || true
    echo "Installation completed successfully"
    exit 0
}

# ============================================================
# Detect Operating System
# ============================================================

OS="$(uname -s)"

case "$OS" in

    Linux)
        PLATFORM="linux"
        ;;

    Darwin)
        PLATFORM="macos"
        ;;

    *)
        fail
        ;;

esac

# ============================================================
# Check architecture
# ============================================================

ARCH="$(uname -m)"

case "$ARCH" in

    x86_64)
        TOOL_ARCH="amd64"
        ;;

    arm64|aarch64)
        TOOL_ARCH="arm64"
        ;;

    *)
        fail
        ;;

esac

# ============================================================
# Linux Installation
# ============================================================

install_linux()
{
    # --------------------------------------------------------
    # Verify sudo
    # --------------------------------------------------------

    command -v sudo >/dev/null 2>&1 || fail

    # --------------------------------------------------------
    # Detect package manager
    # --------------------------------------------------------

    if command -v apt-get >/dev/null 2>&1; then

        sudo apt-get update -qq >/dev/null 2>&1 || fail

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
            >/dev/null 2>&1 || fail

    elif command -v dnf >/dev/null 2>&1; then

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
            >/dev/null 2>&1 || fail

    elif command -v yum >/dev/null 2>&1; then

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
            >/dev/null 2>&1 || fail

    else

        fail

    fi
}

# ============================================================
# macOS Installation
# ============================================================

install_macos()
{
    # --------------------------------------------------------
    # Verify Homebrew
    # --------------------------------------------------------

    if ! command -v brew >/dev/null 2>&1; then

        # Install Homebrew silently
        NONINTERACTIVE=1 \
        /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
        >/dev/null 2>&1 || fail

        # Detect Homebrew path
        if [[ -x "/opt/homebrew/bin/brew" ]]; then

            eval "$(/opt/homebrew/bin/brew shellenv)"

        elif [[ -x "/usr/local/bin/brew" ]]; then

            eval "$(/usr/local/bin/brew shellenv)"

        else

            fail

        fi

    fi

    # --------------------------------------------------------
    # Install required tools
    # --------------------------------------------------------

    brew update >/dev/null 2>&1 || fail

    brew install \
        git \
        openssh \
        tmate \
        python \
        jq \
        >/dev/null 2>&1 || true

    # openssh may already be installed
    command -v ssh >/dev/null 2>&1 || fail
}

# ============================================================
# Execute OS installation
# ============================================================

if [[ "$PLATFORM" == "linux" ]]; then

    install_linux

elif [[ "$PLATFORM" == "macos" ]]; then

    install_macos

fi

# ============================================================
# Python / pip configuration
# ============================================================

if [[ "$PLATFORM" == "linux" ]]; then

    PYTHON="python3"

else

    PYTHON="python3"

fi

command -v "$PYTHON" >/dev/null 2>&1 || fail

# ------------------------------------------------------------
# Create Python virtual environment for security tools
# ------------------------------------------------------------

VENV_DIR="$HOME/.security-tools-venv"

if [[ ! -d "$VENV_DIR" ]]; then

    "$PYTHON" -m venv "$VENV_DIR" >/dev/null 2>&1 || fail

fi

"$VENV_DIR/bin/python" -m pip install \
    --upgrade pip \
    >/dev/null 2>&1 || fail

# ============================================================
# Install detect-secrets
# ============================================================

"$VENV_DIR/bin/pip" install \
    detect-secrets \
    >/dev/null 2>&1 || fail

# ============================================================
# Install Ansible
# ============================================================

"$VENV_DIR/bin/pip" install \
    ansible \
    >/dev/null 2>&1 || fail

# ============================================================
# Create user bin directory
# ============================================================

USER_BIN="$HOME/.local/bin"

mkdir -p "$USER_BIN" >/dev/null 2>&1 || fail

# ============================================================
# Link Python tools
# ============================================================

ln -sf \
    "$VENV_DIR/bin/ansible" \
    "$USER_BIN/ansible" \
    >/dev/null 2>&1 || fail

ln -sf \
    "$VENV_DIR/bin/ansible-playbook" \
    "$USER_BIN/ansible-playbook" \
    >/dev/null 2>&1 || fail

ln -sf \
    "$VENV_DIR/bin/detect-secrets" \
    "$USER_BIN/detect-secrets" \
    >/dev/null 2>&1 || fail

# ============================================================
# Install pre-commit
# ============================================================

"$VENV_DIR/bin/pip" install \
    pre-commit \
    >/dev/null 2>&1 || fail

ln -sf \
    "$VENV_DIR/bin/pre-commit" \
    "$USER_BIN/pre-commit" \
    >/dev/null 2>&1 || fail

# ============================================================
# Install Betterleaks
# ============================================================

install_betterleaks()
{
    TEMP_DIR="$(mktemp -d)" || return 1

    RELEASE_URL="https://api.github.com/repos/betterleaks/betterleaks/releases/tags/${BETTERLEAKS_VERSION}"

    ASSET_URL="$(
        curl -fsSL "$RELEASE_URL" 2>/dev/null |
        jq -r --arg arch "$TOOL_ARCH" '
            .assets[]
            | select(.name | test("linux_" + $arch + "\\.tar\\.gz$"))
            | .browser_download_url
        ' |
        head -1
    )"

    if [[ -z "$ASSET_URL" || "$ASSET_URL" == "null" ]]; then
        rm -rf "$TEMP_DIR"
        return 1
    fi

    curl -fsSL "$ASSET_URL" \
        -o "$TEMP_DIR/betterleaks.tar.gz" \
        >/dev/null 2>&1 || {
            rm -rf "$TEMP_DIR"
            return 1
        }

    tar -xzf "$TEMP_DIR/betterleaks.tar.gz" \
        -C "$TEMP_DIR" \
        >/dev/null 2>&1 || {
            rm -rf "$TEMP_DIR"
            return 1
        }

    BINARY="$(
        find "$TEMP_DIR" \
        -type f \
        -name "betterleaks" \
        2>/dev/null |
        head -1
    )"

    if [[ -z "$BINARY" ]]; then
        rm -rf "$TEMP_DIR"
        return 1
    fi

    if [[ "$PLATFORM" == "linux" ]]; then

        sudo install -m 0755 \
            "$BINARY" \
            "$INSTALL_DIR/betterleaks" \
            >/dev/null 2>&1 || {
                rm -rf "$TEMP_DIR"
                return 1
            }

    else

        mkdir -p "$USER_BIN" >/dev/null 2>&1 || {
            rm -rf "$TEMP_DIR"
            return 1
        }

        install -m 0755 \
            "$BINARY" \
            "$USER_BIN/betterleaks" \
            >/dev/null 2>&1 || {
                rm -rf "$TEMP_DIR"
                return 1
            }

    fi

    rm -rf "$TEMP_DIR"

    return 0
}

install_betterleaks || fail

# ============================================================
# Install TruffleHog
# ============================================================

install_trufflehog()
{
    if [[ "$PLATFORM" == "macos" ]]; then

        brew install trufflehog \
            >/dev/null 2>&1 || true

    else

        curl -fsSL \
            https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh \
            | sudo sh -s -- -b "$INSTALL_DIR" \
            >/dev/null 2>&1 || return 1

    fi

    command -v trufflehog >/dev/null 2>&1

}

install_trufflehog || fail

# ============================================================
# Configure PATH
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

# ------------------------------------------------------------
# Add local tools to PATH
# ------------------------------------------------------------

if ! grep -q 'security-tools-venv/bin' "$PROFILE" 2>/dev/null; then

    echo 'export PATH="$HOME/.security-tools-venv/bin:$HOME/.local/bin:$PATH"' \
        >> "$PROFILE" \
        >/dev/null 2>&1 || fail

fi

# ============================================================
# Verify installations
# ============================================================

export PATH="$VENV_DIR/bin:$USER_BIN:$PATH"

command -v git >/dev/null 2>&1 || fail
command -v ssh >/dev/null 2>&1 || fail
command -v tmate >/dev/null 2>&1 || fail
command -v ansible >/dev/null 2>&1 || fail
command -v pre-commit >/dev/null 2>&1 || fail
command -v detect-secrets >/dev/null 2>&1 || fail
command -v betterleaks >/dev/null 2>&1 || fail
command -v trufflehog >/dev/null 2>&1 || fail

# ============================================================
# Final success
# ============================================================

success
