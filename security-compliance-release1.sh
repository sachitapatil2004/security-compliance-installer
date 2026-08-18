#!/usr/bin/env bash

# ============================================================
# SECURITY COMPLIANCE INSTALLER
# ============================================================
#
# Supported Operating Systems:
#   - Ubuntu / Debian Linux
#   - macOS
#
# Supported Architectures:
#   - x86_64 / amd64
#   - arm64 / aarch64
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
# Output:
#   Installation completed successfully
#   OR
#   Installation failed
#
# All installation output is suppressed.
#
# ============================================================

set -u

# ============================================================
# Configuration
# ============================================================

BETTERLEAKS_VERSION="v1.7.2"

VENV_DIR="$HOME/.security-compliance-venv"
USER_BIN="$HOME/.local/bin"

TEMP_DIR=""

# ============================================================
# Silent execution
# ============================================================

LOG_FILE="$(mktemp /tmp/security-compliance-install.XXXXXX.log 2>/dev/null || echo "/tmp/security-compliance-install.log")"

# Redirect EVERYTHING to temporary log.
# Nothing will be displayed during installation.
exec >"$LOG_FILE" 2>&1

# ============================================================
# Final output functions
# ============================================================

show_success()
{
    rm -f "$LOG_FILE" >/dev/null 2>&1 || true

    if [[ -w /dev/tty ]]; then
        echo "Installation completed successfully" >/dev/tty
    else
        echo "Installation completed successfully"
    fi

    exit 0
}

show_failure()
{
    # User requested no logs.
    rm -f "$LOG_FILE" >/dev/null 2>&1 || true

    if [[ -w /dev/tty ]]; then
        echo "Installation failed" >/dev/tty
    else
        echo "Installation failed"
    fi

    exit 1
}

# ============================================================
# Cleanup
# ============================================================

cleanup()
{
    if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR" >/dev/null 2>&1 || true
    fi
}

trap cleanup EXIT

# ============================================================
# Generic failure handler
# ============================================================

fail()
{
    show_failure
}

# ============================================================
# Detect Operating System
# ============================================================

OS="$(uname -s 2>/dev/null)" || fail

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
# Detect Architecture
# ============================================================

RAW_ARCH="$(uname -m 2>/dev/null)" || fail

case "$RAW_ARCH" in

    x86_64)
        ARCH="amd64"
        ;;

    amd64)
        ARCH="amd64"
        ;;

    arm64)
        ARCH="arm64"
        ;;

    aarch64)
        ARCH="arm64"
        ;;

    *)
        fail
        ;;

esac

# ============================================================
# Check required commands
# ============================================================

command -v curl >/dev/null 2>&1 || {
    # curl may be installed later on Linux/macOS.
    true
}

# ============================================================
# Linux Installation
# ============================================================

install_linux_packages()
{
    command -v sudo >/dev/null 2>&1 || return 1

    # --------------------------------------------------------
    # Ubuntu / Debian
    # --------------------------------------------------------

    if command -v apt-get >/dev/null 2>&1; then

        sudo DEBIAN_FRONTEND=noninteractive \
            apt-get update -qq \
            >/dev/null 2>&1 || return 1

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
            >/dev/null 2>&1 || return 1

        return 0
    fi

    # --------------------------------------------------------
    # Fedora / RHEL
    # --------------------------------------------------------

    if command -v dnf >/dev/null 2>&1; then

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
            >/dev/null 2>&1 || return 1

        return 0
    fi

    # --------------------------------------------------------
    # CentOS / older RHEL
    # --------------------------------------------------------

    if command -v yum >/dev/null 2>&1; then

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
            >/dev/null 2>&1 || return 1

        return 0
    fi

    return 1
}

# ============================================================
# macOS Installation
# ============================================================

install_macos_packages()
{
    # --------------------------------------------------------
    # Check Homebrew
    # --------------------------------------------------------

    if ! command -v brew >/dev/null 2>&1; then

        NONINTERACTIVE=1 \
            /bin/bash -c \
            "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
            >/dev/null 2>&1 || return 1

    fi

    # --------------------------------------------------------
    # Configure Homebrew path
    # --------------------------------------------------------

    if [[ -x "/opt/homebrew/bin/brew" ]]; then

        eval "$(/opt/homebrew/bin/brew shellenv)" \
            >/dev/null 2>&1

    elif [[ -x "/usr/local/bin/brew" ]]; then

        eval "$(/usr/local/bin/brew shellenv)" \
            >/dev/null 2>&1

    fi

    command -v brew >/dev/null 2>&1 || return 1

    # --------------------------------------------------------
    # Install packages
    # --------------------------------------------------------

    brew update \
        >/dev/null 2>&1 || return 1

    brew install \
        git \
        openssh \
        tmate \
        python \
        jq \
        wget \
        >/dev/null 2>&1 || true

    # --------------------------------------------------------
    # Verify important tools
    # --------------------------------------------------------

    command -v git >/dev/null 2>&1 || return 1
    command -v ssh >/dev/null 2>&1 || return 1
    command -v tmate >/dev/null 2>&1 || return 1
    command -v python3 >/dev/null 2>&1 || return 1

    return 0
}

# ============================================================
# Install OS packages
# ============================================================

if [[ "$PLATFORM" == "linux" ]]; then

    install_linux_packages || fail

elif [[ "$PLATFORM" == "macos" ]]; then

    install_macos_packages || fail

fi

# ============================================================
# Prepare directories
# ============================================================

mkdir -p "$USER_BIN" >/dev/null 2>&1 || fail

# ============================================================
# Python detection
# ============================================================

PYTHON=""

if command -v python3 >/dev/null 2>&1; then

    PYTHON="$(command -v python3)"

elif command -v python >/dev/null 2>&1; then

    PYTHON="$(command -v python)"

else

    fail

fi

# ============================================================
# Create Python virtual environment
# ============================================================

if [[ ! -d "$VENV_DIR" ]]; then

    "$PYTHON" -m venv "$VENV_DIR" \
        >/dev/null 2>&1 || fail

fi

# ============================================================
# Upgrade pip silently
# ============================================================

"$VENV_DIR/bin/python" \
    -m pip install \
    --upgrade pip \
    >/dev/null 2>&1 || fail

# ============================================================
# Install Ansible
# ============================================================

"$VENV_DIR/bin/python" \
    -m pip install \
    ansible \
    >/dev/null 2>&1 || fail

# ============================================================
# Install detect-secrets
# ============================================================

"$VENV_DIR/bin/python" \
    -m pip install \
    detect-secrets \
    >/dev/null 2>&1 || fail

# ============================================================
# Install pre-commit
# ============================================================

"$VENV_DIR/bin/python" \
    -m pip install \
    pre-commit \
    >/dev/null 2>&1 || fail

# ============================================================
# Create links for Python tools
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

ln -sf \
    "$VENV_DIR/bin/pre-commit" \
    "$USER_BIN/pre-commit" \
    >/dev/null 2>&1 || fail

# ============================================================
# Add tools to current PATH
# ============================================================

export PATH="$VENV_DIR/bin:$USER_BIN:$PATH"

# ============================================================
# Install Betterleaks
# ============================================================

install_betterleaks()
{
    TEMP_DIR="$(mktemp -d)" || return 1

    # --------------------------------------------------------
    # Get official latest release metadata
    # --------------------------------------------------------

    RELEASE_JSON="$(
        curl -fsSL \
        "https://api.github.com/repos/betterleaks/betterleaks/releases/tags/${BETTERLEAKS_VERSION}"
    )" || return 1

    # --------------------------------------------------------
    # Determine operating-system pattern
    # --------------------------------------------------------

    if [[ "$PLATFORM" == "linux" ]]; then

        OS_PATTERN="linux"

    else

        OS_PATTERN="darwin|macos"
    fi

    # --------------------------------------------------------
    # Determine architecture pattern
    # --------------------------------------------------------

    if [[ "$ARCH" == "amd64" ]]; then

        ARCH_PATTERN="amd64|x86_64"

    else

        ARCH_PATTERN="arm64|aarch64"
    fi

    # --------------------------------------------------------
    # Find correct release asset
    # --------------------------------------------------------

    ASSET_URL="$(
        echo "$RELEASE_JSON" |
        jq -r \
        --arg os "$OS_PATTERN" \
        --arg arch "$ARCH_PATTERN" '
            .assets[]
            | select(
                (.name | ascii_downcase | test($os))
                and
                (.name | ascii_downcase | test($arch))
                and
                (.name | ascii_downcase | test("\\.(tar\\.gz|tgz)$"))
            )
            | .browser_download_url
        ' |
        head -1
    )"

    # --------------------------------------------------------
    # Validate asset
    # --------------------------------------------------------

    if [[ -z "$ASSET_URL" || "$ASSET_URL" == "null" ]]; then
        return 1
    fi

    # --------------------------------------------------------
    # Download Betterleaks
    # --------------------------------------------------------

    curl -fsSL \
        "$ASSET_URL" \
        -o "$TEMP_DIR/betterleaks.tar.gz" \
        >/dev/null 2>&1 || return 1

    # --------------------------------------------------------
    # Extract
    # --------------------------------------------------------

    tar -xzf \
        "$TEMP_DIR/betterleaks.tar.gz" \
        -C "$TEMP_DIR" \
        >/dev/null 2>&1 || return 1

    # --------------------------------------------------------
    # Find binary
    # --------------------------------------------------------

    BINARY="$(
        find "$TEMP_DIR" \
            -type f \
            -name "betterleaks" \
            2>/dev/null |
        head -1
    )"

    if [[ -z "$BINARY" ]]; then
        return 1
    fi

    # --------------------------------------------------------
    # Install Linux binary
    # --------------------------------------------------------

    if [[ "$PLATFORM" == "linux" ]]; then

        command -v sudo >/dev/null 2>&1 || return 1

        sudo install \
            -m 0755 \
            "$BINARY" \
            "/usr/local/bin/betterleaks" \
            >/dev/null 2>&1 || return 1

    # --------------------------------------------------------
    # Install macOS binary
    # --------------------------------------------------------

    else

        mkdir -p "$USER_BIN" \
            >/dev/null 2>&1 || return 1

        install \
            -m 0755 \
            "$BINARY" \
            "$USER_BIN/betterleaks" \
            >/dev/null 2>&1 || return 1

    fi

    return 0
}

install_betterleaks || fail

# ============================================================
# Install TruffleHog
# ============================================================

install_trufflehog()
{
    # --------------------------------------------------------
    # macOS
    # --------------------------------------------------------

    if [[ "$PLATFORM" == "macos" ]]; then

        brew install trufflehog \
            >/dev/null 2>&1 || true

        command -v trufflehog >/dev/null 2>&1

        return $?
    fi

    # --------------------------------------------------------
    # Linux
    # --------------------------------------------------------

    if command -v trufflehog >/dev/null 2>&1; then
        return 0
    fi

    command -v sudo >/dev/null 2>&1 || return 1

    curl -fsSL \
        https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh |
        sudo sh -s -- \
        -b /usr/local/bin \
        >/dev/null 2>&1 || return 1

    command -v trufflehog >/dev/null 2>&1

    return $?
}

install_trufflehog || fail

# ============================================================
# Verify all required tools
# ============================================================

export PATH="$VENV_DIR/bin:$USER_BIN:$PATH"

command -v git \
    >/dev/null 2>&1 || fail

command -v ssh \
    >/dev/null 2>&1 || fail

command -v tmate \
    >/dev/null 2>&1 || fail

command -v ansible \
    >/dev/null 2>&1 || fail

command -v ansible-playbook \
    >/dev/null 2>&1 || fail

command -v detect-secrets \
    >/dev/null 2>&1 || fail

command -v pre-commit \
    >/dev/null 2>&1 || fail

command -v betterleaks \
    >/dev/null 2>&1 || fail

command -v trufflehog \
    >/dev/null 2>&1 || fail

# ============================================================
# Configure shell PATH
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

# ============================================================
# Add PATH permanently
# ============================================================

if ! grep -Fq \
    '.security-compliance-venv/bin' \
    "$PROFILE" \
    2>/dev/null; then

    printf '\nexport PATH="$HOME/.security-compliance-venv/bin:$HOME/.local/bin:$PATH"\n' \
        >> "$PROFILE" \
        2>/dev/null || fail

fi

# ============================================================
# Final verification
# ============================================================

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

git \
    --version \
    >/dev/null 2>&1 || fail

ssh \
    -V \
    >/dev/null 2>&1 || true

tmate \
    -V \
    >/dev/null 2>&1 || fail

# ============================================================
# SUCCESS
# ============================================================

show_success
