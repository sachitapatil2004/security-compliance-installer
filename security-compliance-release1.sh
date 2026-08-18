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
#   Git
#   OpenSSH
#   tmate
#   Ansible
#   Betterleaks
#   TruffleHog
#   detect-secrets
#   pre-commit
#
# Terminal output:
#
#   Installation completed successfully
#
# OR
#
#   Installation failed
#
# ============================================================

set -u

# ============================================================
# CONFIGURATION
# ============================================================

VENV_DIR="$HOME/.security-compliance-venv"
USER_BIN="$HOME/.local/bin"
GO_VERSION="1.24.6"

LOG_FILE="/tmp/security-compliance-install-$$.log"

# ============================================================
# SILENT MODE
# ============================================================

exec >"$LOG_FILE" 2>&1

# ============================================================
# CLEANUP
# ============================================================

cleanup()
{
    rm -f "$LOG_FILE" >/dev/null 2>&1 || true

    if [[ -n "${TMP_DIR:-}" && -d "${TMP_DIR:-}" ]]; then
        rm -rf "$TMP_DIR" >/dev/null 2>&1 || true
    fi
}

trap cleanup EXIT

# ============================================================
# FINAL STATUS
# ============================================================

success()
{
    cleanup

    printf '%s\n' "Installation completed successfully" >/dev/tty 2>/dev/null || \
    printf '%s\n' "Installation completed successfully"

    exit 0
}

failure()
{
    cleanup

    printf '%s\n' "Installation failed" >/dev/tty 2>/dev/null || \
    printf '%s\n' "Installation failed"

    exit 1
}

fail()
{
    failure
}

# ============================================================
# DETECT OS
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
# DETECT ARCHITECTURE
# ============================================================

ARCH_RAW="$(uname -m 2>/dev/null)" || fail

case "$ARCH_RAW" in

    x86_64|amd64)
        ARCH="amd64"
        ;;

    arm64|aarch64)
        ARCH="arm64"
        ;;

    *)
        fail
        ;;

esac

# ============================================================
# CREATE USER BIN
# ============================================================

mkdir -p "$USER_BIN" >/dev/null 2>&1 || fail

# ============================================================
# LINUX PACKAGE INSTALLATION
# ============================================================

install_linux_packages()
{
    command -v sudo >/dev/null 2>&1 || return 1

    # --------------------------------------------------------
    # Debian / Ubuntu
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
            build-essential \
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
            gcc \
            make \
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
            gcc \
            make \
            >/dev/null 2>&1 || return 1

        return 0
    fi

    return 1
}

# ============================================================
# MACOS PACKAGE INSTALLATION
# ============================================================

install_macos_packages()
{
    # --------------------------------------------------------
    # Install Homebrew if required
    # --------------------------------------------------------

    if ! command -v brew >/dev/null 2>&1; then

        NONINTERACTIVE=1 \
        /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
        >/dev/null 2>&1 || return 1

    fi

    # --------------------------------------------------------
    # Configure Homebrew PATH
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
    # Update Homebrew
    # --------------------------------------------------------

    brew update >/dev/null 2>&1 || return 1

    # --------------------------------------------------------
    # Install required packages
    # --------------------------------------------------------

    brew install \
        git \
        openssh \
        tmate \
        python \
        wget \
        jq \
        go \
        >/dev/null 2>&1 || true

    # --------------------------------------------------------
    # Verify basic packages
    # --------------------------------------------------------

    command -v git >/dev/null 2>&1 || return 1
    command -v ssh >/dev/null 2>&1 || return 1
    command -v tmate >/dev/null 2>&1 || return 1
    command -v python3 >/dev/null 2>&1 || return 1
    command -v go >/dev/null 2>&1 || return 1

    return 0
}

# ============================================================
# INSTALL OS PACKAGES
# ============================================================

if [[ "$PLATFORM" == "linux" ]]; then

    install_linux_packages || fail

else

    install_macos_packages || fail

fi

# ============================================================
# PYTHON
# ============================================================

if command -v python3 >/dev/null 2>&1; then

    PYTHON="$(command -v python3)"

else

    fail

fi

# ============================================================
# PYTHON VIRTUAL ENVIRONMENT
# ============================================================

if [[ ! -d "$VENV_DIR" ]]; then

    "$PYTHON" -m venv "$VENV_DIR" \
        >/dev/null 2>&1 || fail

fi

# ============================================================
# UPGRADE PIP
# ============================================================

"$VENV_DIR/bin/python" \
    -m pip install --upgrade pip \
    >/dev/null 2>&1 || fail

# ============================================================
# INSTALL ANSIBLE
# ============================================================

"$VENV_DIR/bin/python" \
    -m pip install ansible \
    >/dev/null 2>&1 || fail

# ============================================================
# INSTALL DETECT-SECRETS
# ============================================================

"$VENV_DIR/bin/python" \
    -m pip install detect-secrets \
    >/dev/null 2>&1 || fail

# ============================================================
# INSTALL PRE-COMMIT
# ============================================================

"$VENV_DIR/bin/python" \
    -m pip install pre-commit \
    >/dev/null 2>&1 || fail

# ============================================================
# LINK PYTHON TOOLS
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
# PATH
# ============================================================

export PATH="$VENV_DIR/bin:$USER_BIN:$PATH"

# ============================================================
# INSTALL BETTERLEAKS
# ============================================================
#
# Betterleaks officially supports:
#
#   brew install betterleaks
#   go install github.com/betterleaks/betterleaks@latest
#
# We use:
#
#   macOS -> Homebrew
#   Linux -> Go
#
# This avoids depending on release asset filenames.
#
# ============================================================

install_betterleaks()
{
    # --------------------------------------------------------
    # macOS
    # --------------------------------------------------------

    if [[ "$PLATFORM" == "macos" ]]; then

        brew install betterleaks \
            >/dev/null 2>&1 || return 1

        command -v betterleaks >/dev/null 2>&1

        return $?
    fi

    # --------------------------------------------------------
    # Linux
    # --------------------------------------------------------

    if ! command -v go >/dev/null 2>&1; then

        # Install Go through apt if possible
        if command -v apt-get >/dev/null 2>&1; then

            sudo DEBIAN_FRONTEND=noninteractive \
                apt-get install -y -qq golang-go \
                >/dev/null 2>&1 || return 1

        elif command -v dnf >/dev/null 2>&1; then

            sudo dnf install -y golang \
                >/dev/null 2>&1 || return 1

        else

            return 1

        fi

    fi

    command -v go >/dev/null 2>&1 || return 1

    # --------------------------------------------------------
    # Go binary destination
    # --------------------------------------------------------

    export GOPATH="${GOPATH:-$HOME/go}"

    mkdir -p "$GOPATH/bin" \
        >/dev/null 2>&1 || return 1

    export PATH="$GOPATH/bin:$PATH"

    # --------------------------------------------------------
    # Install Betterleaks
    # --------------------------------------------------------

    go install \
        github.com/betterleaks/betterleaks@v1.7.2 \
        >/dev/null 2>&1 || return 1

    # --------------------------------------------------------
    # Verify
    # --------------------------------------------------------

    if [[ -x "$GOPATH/bin/betterleaks" ]]; then

        ln -sf \
            "$GOPATH/bin/betterleaks" \
            "$USER_BIN/betterleaks" \
            >/dev/null 2>&1 || return 1

    else

        return 1

    fi

    command -v betterleaks >/dev/null 2>&1

    return $?
}

install_betterleaks || fail

# ============================================================
# INSTALL TRUFFLEHOG
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
        sudo sh -s -- -b /usr/local/bin \
        >/dev/null 2>&1 || return 1

    command -v trufflehog >/dev/null 2>&1

    return $?
}

install_trufflehog || fail

# ============================================================
# VERIFY INSTALLATIONS
# ============================================================

export PATH="$VENV_DIR/bin:$USER_BIN:$HOME/go/bin:$PATH"

command -v git >/dev/null 2>&1 || fail
command -v ssh >/dev/null 2>&1 || fail
command -v tmate >/dev/null 2>&1 || fail
command -v ansible >/dev/null 2>&1 || fail
command -v ansible-playbook >/dev/null 2>&1 || fail
command -v detect-secrets >/dev/null 2>&1 || fail
command -v pre-commit >/dev/null 2>&1 || fail
command -v betterleaks >/dev/null 2>&1 || fail
command -v trufflehog >/dev/null 2>&1 || fail

# ============================================================
# SHELL CONFIGURATION
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
# PERMANENT PATH
# ============================================================

PATH_LINE='export PATH="$HOME/.security-compliance-venv/bin:$HOME/.local/bin:$HOME/go/bin:$PATH"'

if ! grep -Fq \
    '.security-compliance-venv/bin' \
    "$PROFILE" \
    2>/dev/null; then

    printf '\n%s\n' "$PATH_LINE" \
        >> "$PROFILE" \
        2>/dev/null || fail

fi

# ============================================================
# FINAL TOOL VERIFICATION
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

tmate \
    -V \
    >/dev/null 2>&1 || fail

# ============================================================
# SUCCESS
# ============================================================

success
