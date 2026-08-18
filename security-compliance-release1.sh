#!/usr/bin/env bash

# ============================================================
# Security Compliance Release 1
#
# Supported:
#   - Ubuntu / Debian
#   - Fedora / RHEL
#   - CentOS
#   - SUSE
#   - macOS Intel
#   - macOS Apple Silicon
#   - Windows through Git Bash
#
# Installs:
#   - Gitleaks 8.30.0
#   - Global Git pre-commit secret scanning
#   - Linux:
#       tmate
#       Ansible
#       OpenSSH client
#       OpenSSH server
#   - macOS:
#       tmate
#       Ansible
#       OpenSSH client
#
# Output:
#   Only clean installation status messages are displayed.
#   Package-manager logs are hidden.
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
# Output
# ============================================================

info() {
    echo "[INFO] $1"
}

success() {
    echo "[SUCCESS] $1"
}

warning() {
    echo "[WARNING] $1"
}

error() {
    echo "[ERROR] $1"
}

fail() {
    echo ""
    error "$1"
    echo ""
    error "Security Compliance installation failed."
    exit 1
}

# ============================================================
# Cleanup
# ============================================================

cleanup() {

    if [ -n "${TMP_ROOT:-}" ] && [ -d "$TMP_ROOT" ]; then
        rm -rf "$TMP_ROOT"
    fi
}

trap cleanup EXIT

# ============================================================
# Header
# ============================================================

clear 2>/dev/null || true

echo ""
echo "============================================================"
echo "       SECURITY COMPLIANCE INSTALLER"
echo "       Version: $VERSION"
echo "============================================================"
echo ""

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
        fail "Unsupported operating system: $RAW_OS"
        ;;

esac

# ============================================================
# Detect OS Version
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
        sw_vers -productVersion 2>/dev/null || echo "Unknown"
    )"

elif [ "$PLATFORM" = "windows" ]; then

    OS_NAME="Windows"
    OS_VERSION="Git Bash"

fi

echo ""
info "Operating System : $OS_NAME"
info "OS Version       : $OS_VERSION"
info "Architecture     : $ARCH"
info "Platform         : $PLATFORM"
echo ""

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
        fail "Unsupported CPU architecture: $ARCH"
        ;;

esac

success "Architecture detected: $GITLEAKS_ARCH"

# ============================================================
# Check Git
# ============================================================

if ! command -v git >/dev/null 2>&1; then
    fail "Git is required. Please install Git and run again."
fi

success "Git detected: $(git --version)"

# ============================================================
# Check curl
# ============================================================

if ! command -v curl >/dev/null 2>&1; then
    fail "curl is required. Please install curl and run again."
fi

success "curl is available."

# ============================================================
# Create directories
# ============================================================

mkdir -p "$BIN_DIR" || fail "Unable to create installation directory."
mkdir -p "$CONFIG_DIR" || fail "Unable to create configuration directory."
mkdir -p "$HOOK_DIR" || fail "Unable to create Git hooks directory."

export PATH="$BIN_DIR:$PATH"

success "Security Compliance directories ready."

# ============================================================
# Gitleaks Path
# ============================================================

if [ "$PLATFORM" = "windows" ]; then
    GITLEAKS="$BIN_DIR/gitleaks.exe"
else
    GITLEAKS="$BIN_DIR/gitleaks"
fi

# ============================================================
# Install Gitleaks
# ============================================================

install_gitleaks() {

    local installed_version=""

    if [ -f "$GITLEAKS" ] || [ -x "$GITLEAKS" ]; then

        installed_version="$(
            "$GITLEAKS" version 2>/dev/null || true
        )"

        if [ "$installed_version" = "$GITLEAKS_VERSION" ]; then

            success "Gitleaks $GITLEAKS_VERSION is already installed."
            return 0

        fi

        info "Updating Gitleaks to version $GITLEAKS_VERSION..."

    else

        info "Installing Gitleaks $GITLEAKS_VERSION..."

    fi

    TMP_ROOT="$(mktemp -d)" || fail "Unable to create temporary directory."

    if [ "$PLATFORM" = "linux" ]; then

        ARCHIVE="gitleaks_${GITLEAKS_VERSION}_linux_${GITLEAKS_ARCH}.tar.gz"

        URL="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${ARCHIVE}"

        if ! curl \
            --fail \
            --silent \
            --show-error \
            --location \
            --proto '=https' \
            --tlsv1.2 \
            --retry 3 \
            "$URL" \
            -o "$TMP_ROOT/gitleaks.tar.gz" \
            >/dev/null 2>&1; then

            fail "Unable to download Gitleaks."
        fi

        if ! tar \
            -xzf "$TMP_ROOT/gitleaks.tar.gz" \
            -C "$TMP_ROOT" \
            >/dev/null 2>&1; then

            fail "Unable to extract Gitleaks."
        fi

        if [ ! -f "$TMP_ROOT/gitleaks" ]; then
            fail "Gitleaks binary was not found."
        fi

        if ! install \
            -m 0755 \
            "$TMP_ROOT/gitleaks" \
            "$GITLEAKS" \
            >/dev/null 2>&1; then

            fail "Unable to install Gitleaks."
        fi

    elif [ "$PLATFORM" = "darwin" ]; then

        ARCHIVE="gitleaks_${GITLEAKS_VERSION}_darwin_${GITLEAKS_ARCH}.tar.gz"

        URL="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${ARCHIVE}"

        if ! curl \
            --fail \
            --silent \
            --show-error \
            --location \
            --proto '=https' \
            --tlsv1.2 \
            --retry 3 \
            "$URL" \
            -o "$TMP_ROOT/gitleaks.tar.gz" \
            >/dev/null 2>&1; then

            fail "Unable to download Gitleaks."
        fi

        if ! tar \
            -xzf "$TMP_ROOT/gitleaks.tar.gz" \
            -C "$TMP_ROOT" \
            >/dev/null 2>&1; then

            fail "Unable to extract Gitleaks."
        fi

        if [ ! -f "$TMP_ROOT/gitleaks" ]; then
            fail "Gitleaks binary was not found."
        fi

        if ! install \
            -m 0755 \
            "$TMP_ROOT/gitleaks" \
            "$GITLEAKS" \
            >/dev/null 2>&1; then

            fail "Unable to install Gitleaks."
        fi

    elif [ "$PLATFORM" = "windows" ]; then

        ARCHIVE="gitleaks_${GITLEAKS_VERSION}_windows_${GITLEAKS_ARCH}.zip"

        URL="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${ARCHIVE}"

        if ! curl \
            --fail \
            --silent \
            --show-error \
            --location \
            --proto '=https' \
            --tlsv1.2 \
            --retry 3 \
            "$URL" \
            -o "$TMP_ROOT/gitleaks.zip" \
            >/dev/null 2>&1; then

            fail "Unable to download Gitleaks."
        fi

        if command -v unzip >/dev/null 2>&1; then

            unzip -q \
                "$TMP_ROOT/gitleaks.zip" \
                -d "$TMP_ROOT" \
                >/dev/null 2>&1 || fail "Unable to extract Gitleaks."

        elif command -v powershell.exe >/dev/null 2>&1; then

            ZIP_WIN="$(cygpath -w "$TMP_ROOT/gitleaks.zip")"
            DEST_WIN="$(cygpath -w "$TMP_ROOT")"

            powershell.exe \
                -NoProfile \
                -NonInteractive \
                -Command \
                "Expand-Archive -Force '$ZIP_WIN' '$DEST_WIN'" \
                >/dev/null 2>&1 \
                || fail "Unable to extract Gitleaks."

        else

            fail "unzip or PowerShell is required."

        fi

        if [ ! -f "$TMP_ROOT/gitleaks.exe" ]; then
            fail "Gitleaks executable was not found."
        fi

        cp "$TMP_ROOT/gitleaks.exe" "$GITLEAKS" \
            >/dev/null 2>&1 \
            || fail "Unable to install Gitleaks."

        chmod +x "$GITLEAKS" 2>/dev/null || true

    fi

    success "Gitleaks $GITLEAKS_VERSION installed successfully."
}

install_gitleaks

# ============================================================
# Verify Gitleaks
# ============================================================

INSTALLED_VERSION="$(
    "$GITLEAKS" version 2>/dev/null || true
)"

if [ "$INSTALLED_VERSION" != "$GITLEAKS_VERSION" ]; then
    fail "Gitleaks verification failed. Expected $GITLEAKS_VERSION, found $INSTALLED_VERSION."
fi

success "Gitleaks verified: $INSTALLED_VERSION"

# ============================================================
# Gitleaks Configuration
# ============================================================

info "Configuring secret detection..."

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

chmod 600 "$CONFIG_FILE"

success "Secret detection rules configured."

# ============================================================
# Global Git Pre-Commit Hook
# ============================================================

info "Configuring global Git secret scanning..."

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
    echo "[ERROR] Gitleaks scanner is unavailable."
    echo "[ERROR] Commit blocked."
    exit 1
fi

if [ ! -f "$CONFIG" ]; then
    echo "[ERROR] Gitleaks configuration is unavailable."
    echo "[ERROR] Commit blocked."
    exit 1
fi

TEMP_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$TEMP_DIR"
}

trap cleanup EXIT

FOUND_LEAK=0

while IFS= read -r -d '' FILE; do

    HASH="$(
        printf '%s' "$FILE" |
        sha256sum |
        cut -d' ' -f1
    )"

    TEMP_FILE="$TEMP_DIR/$HASH"

    if ! git show ":$FILE" > "$TEMP_FILE" 2>/dev/null; then

        echo "[ERROR] Unable to read staged file: $FILE"

        FOUND_LEAK=1
        continue

    fi

    SCAN_OUTPUT="$(
        "$GITLEAKS" dir "$TEMP_FILE" \
            --config "$CONFIG" \
            --redact \
            --no-banner \
            --exit-code 1 \
            2>&1
    )"

    EXIT_CODE=$?

    if [ "$EXIT_CODE" -eq 1 ]; then

        echo ""
        echo "=================================================="
        echo "       SECRET DETECTED"
        echo "=================================================="
        echo ""
        echo "File:"
        echo "  $FILE"
        echo ""
        echo "$SCAN_OUTPUT"
        echo ""
        echo "Commit blocked."
        echo ""

        FOUND_LEAK=1

    elif [ "$EXIT_CODE" -ne 0 ]; then

        echo ""
        echo "[ERROR] Gitleaks scan failed."
        echo "$SCAN_OUTPUT"
        echo ""
        echo "Commit blocked."

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

echo "[SUCCESS] No secrets detected."
exit 0
HOOK

chmod 700 "$HOOK_FILE"

git config --global core.hooksPath "$HOOK_DIR" \
    || fail "Unable to configure global Git hooks."

success "Global Git secret scanning enabled."

# ============================================================
# Generic Package Installation Helper
# ============================================================

install_package() {

    TOOL_NAME="$1"
    PACKAGE_NAME="$2"

    case "$PACKAGE_MANAGER" in

        apt)

            if sudo apt-get install -y "$PACKAGE_NAME" \
                >/dev/null 2>&1; then

                success "$TOOL_NAME installed successfully."

            else

                warning "$TOOL_NAME installation failed."

                return 1
            fi
            ;;

        dnf)

            if sudo dnf install -y "$PACKAGE_NAME" \
                >/dev/null 2>&1; then

                success "$TOOL_NAME installed successfully."

            else

                warning "$TOOL_NAME installation failed."

                return 1
            fi
            ;;

        yum)

            if sudo yum install -y "$PACKAGE_NAME" \
                >/dev/null 2>&1; then

                success "$TOOL_NAME installed successfully."

            else

                warning "$TOOL_NAME installation failed."

                return 1
            fi
            ;;

        zypper)

            if sudo zypper \
                --non-interactive \
                install \
                "$PACKAGE_NAME" \
                >/dev/null 2>&1; then

                success "$TOOL_NAME installed successfully."

            else

                warning "$TOOL_NAME installation failed."

                return 1
            fi
            ;;

    esac

    return 0
}

# ============================================================
# Linux Tools
# ============================================================

install_linux_tools() {

    [ "$PLATFORM" = "linux" ] || return 0

    echo ""
    echo "============================================================"
    echo "       INSTALLING LINUX DEVOPS TOOLS"
    echo "============================================================"
    echo ""

    if ! command -v sudo >/dev/null 2>&1; then
        fail "sudo is required to install Linux tools."
    fi

    if command -v apt-get >/dev/null 2>&1; then

        PACKAGE_MANAGER="apt"

    elif command -v dnf >/dev/null 2>&1; then

        PACKAGE_MANAGER="dnf"

    elif command -v yum >/dev/null 2>&1; then

        PACKAGE_MANAGER="yum"

    elif command -v zypper >/dev/null 2>&1; then

        PACKAGE_MANAGER="zypper"

    else

        fail "Unsupported Linux package manager."
    fi

    info "Preparing package manager..."

    # Do not show apt output.
    if [ "$PACKAGE_MANAGER" = "apt" ]; then

        if ! sudo apt-get update -y >/dev/null 2>&1; then

            warning "Package repository update failed."
            warning "Continuing with existing package information."

        else

            success "Package information updated."

        fi

    fi

    # --------------------------------------------------------
    # tmate
    # --------------------------------------------------------

    if command -v tmate >/dev/null 2>&1; then

        success "tmate is already installed."

    else

        info "Installing tmate..."

        install_package "tmate" "tmate" || true

    fi

    # --------------------------------------------------------
    # OpenSSH Client
    # --------------------------------------------------------

    if command -v ssh >/dev/null 2>&1; then

        success "OpenSSH client is already installed."

    else

        info "Installing OpenSSH client..."

        if [ "$PACKAGE_MANAGER" = "apt" ]; then
            install_package "OpenSSH client" "openssh-client" || true
        else
            install_package "OpenSSH client" "openssh-clients" || true
        fi

    fi

    # --------------------------------------------------------
    # OpenSSH Server
    # --------------------------------------------------------

    if command -v sshd >/dev/null 2>&1; then

        success "OpenSSH server is already installed."

    else

        info "Installing OpenSSH server..."

        if [ "$PACKAGE_MANAGER" = "apt" ]; then
            install_package "OpenSSH server" "openssh-server" || true
        else
            install_package "OpenSSH server" "openssh-server" || true
        fi

    fi

    # --------------------------------------------------------
    # Ansible
    # --------------------------------------------------------

    if command -v ansible >/dev/null 2>&1; then

        success "Ansible is already installed."

    else

        info "Installing Ansible..."

        install_package "Ansible" "ansible" || true

    fi

    # --------------------------------------------------------
    # SSH Service
    # --------------------------------------------------------

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

    echo ""
    info "Linux DevOps tools verification..."

    if command -v tmate >/dev/null 2>&1; then
        success "tmate: INSTALLED"
    else
        warning "tmate: NOT INSTALLED"
    fi

    if command -v ansible >/dev/null 2>&1; then
        success "Ansible: INSTALLED"
    else
        warning "Ansible: NOT INSTALLED"
    fi

    if command -v ssh >/dev/null 2>&1; then
        success "OpenSSH client: INSTALLED"
    else
        warning "OpenSSH client: NOT INSTALLED"
    fi

    if command -v sshd >/dev/null 2>&1; then
        success "OpenSSH server: INSTALLED"
    else
        warning "OpenSSH server: NOT INSTALLED"
    fi
}

# ============================================================
# macOS Tools
# ============================================================

install_macos_tools() {

    [ "$PLATFORM" = "darwin" ] || return 0

    echo ""
    echo "============================================================"
    echo "       INSTALLING macOS DEVOPS TOOLS"
    echo "============================================================"
    echo ""

    if ! command -v brew >/dev/null 2>&1; then

        info "Homebrew is not installed."
        info "Installing Homebrew..."

        if ! /bin/bash -c \
            "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
            >/dev/null 2>&1; then

            fail "Homebrew installation failed."

        fi

        if [ -x "/opt/homebrew/bin/brew" ]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [ -x "/usr/local/bin/brew" ]; then
            eval "$(/usr/local/bin/brew shellenv)"
        fi

    fi

    if ! command -v brew >/dev/null 2>&1; then
        fail "Homebrew is unavailable."
    fi

    success "Homebrew is available."

    # --------------------------------------------------------
    # tmate
    # --------------------------------------------------------

    if command -v tmate >/dev/null 2>&1; then

        success "tmate is already installed."

    else

        info "Installing tmate..."

        if brew install tmate >/dev/null 2>&1; then
            success "tmate installed successfully."
        else
            warning "tmate installation failed."
        fi

    fi

    # --------------------------------------------------------
    # Ansible
    # --------------------------------------------------------

    if command -v ansible >/dev/null 2>&1; then

        success "Ansible is already installed."

    else

        info "Installing Ansible..."

        if brew install ansible >/dev/null 2>&1; then
            success "Ansible installed successfully."
        else
            warning "Ansible installation failed."
        fi

    fi

    # --------------------------------------------------------
    # OpenSSH
    # --------------------------------------------------------

    if command -v ssh >/dev/null 2>&1; then

        success "OpenSSH client is already available."

    else

        info "Installing OpenSSH..."

        if brew install openssh >/dev/null 2>&1; then
            success "OpenSSH client installed successfully."
        else
            warning "OpenSSH installation failed."
        fi

    fi

    echo ""
    info "macOS DevOps tools verification..."

    command -v tmate >/dev/null 2>&1 &&
        success "tmate: INSTALLED" ||
        warning "tmate: NOT INSTALLED"

    command -v ansible >/dev/null 2>&1 &&
        success "Ansible: INSTALLED" ||
        warning "Ansible: NOT INSTALLED"

    command -v ssh >/dev/null 2>&1 &&
        success "OpenSSH client: INSTALLED" ||
        warning "OpenSSH client: NOT INSTALLED"
}

# ============================================================
# Run Tool Installation
# ============================================================

install_linux_tools
install_macos_tools

# ============================================================
# Persistent PATH
# ============================================================

if [ "$PLATFORM" = "darwin" ]; then
    PROFILE_FILE="$HOME/.zshrc"
else
    PROFILE_FILE="$HOME/.bashrc"
fi

if [ ! -f "$PROFILE_FILE" ]; then
    touch "$PROFILE_FILE"
fi

if ! grep -Fq '.security-compliance/bin' "$PROFILE_FILE" 2>/dev/null; then

    {
        echo ""
        echo "# Security Compliance Gitleaks"
        echo 'export PATH="$HOME/.security-compliance/bin:$PATH"'
    } >> "$PROFILE_FILE"

fi

success "Gitleaks PATH configured."

# ============================================================
# Final Verification
# ============================================================

echo ""
echo "============================================================"
echo "       FINAL VERIFICATION"
echo "============================================================"
echo ""

if "$GITLEAKS" version >/dev/null 2>&1; then
    success "Gitleaks: INSTALLED"
else
    fail "Gitleaks verification failed."
fi

if [ -f "$CONFIG_FILE" ]; then
    success "Gitleaks configuration: CREATED"
else
    fail "Gitleaks configuration missing."
fi

if [ -f "$HOOK_FILE" ]; then
    success "Global Git pre-commit hook: CREATED"
else
    fail "Git pre-commit hook missing."
fi

HOOK_PATH="$(
    git config --global --get core.hooksPath 2>/dev/null || true
)"

if [ "$HOOK_PATH" = "$HOOK_DIR" ]; then
    success "Global Git hooks: ENABLED"
else
    fail "Global Git hooks configuration failed."
fi

# ============================================================
# Final Summary
# ============================================================

echo ""
echo "============================================================"
echo "       SECURITY COMPLIANCE INSTALLATION COMPLETE"
echo "============================================================"
echo ""

success "Security Compliance installation completed."

echo ""
echo "Installed components:"
echo ""

success "Gitleaks $GITLEAKS_VERSION"
success "Global Git secret scanning"

if [ "$PLATFORM" = "linux" ]; then

    command -v tmate >/dev/null 2>&1 &&
        success "tmate" ||
        warning "tmate"

    command -v ansible >/dev/null 2>&1 &&
        success "Ansible" ||
        warning "Ansible"

    command -v ssh >/dev/null 2>&1 &&
        success "OpenSSH client" ||
        warning "OpenSSH client"

    command -v sshd >/dev/null 2>&1 &&
        success "OpenSSH server" ||
        warning "OpenSSH server"

elif [ "$PLATFORM" = "darwin" ]; then

    command -v tmate >/dev/null 2>&1 &&
        success "tmate" ||
        warning "tmate"

    command -v ansible >/dev/null 2>&1 &&
        success "Ansible" ||
        warning "Ansible"

    command -v ssh >/dev/null 2>&1 &&
        success "OpenSSH client" ||
        warning "OpenSSH client"

fi

echo ""
echo "Installation directory:"
echo "  $INSTALL_ROOT"
echo ""
echo "Git hooks:"
echo "  $HOOK_DIR"
echo ""
echo "============================================================"
echo ""

exit 0
