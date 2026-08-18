#!/usr/bin/env bash

# ============================================================
# Security Compliance Release 1
#
# Supported:
#   - Ubuntu Linux
#   - Debian Linux
#   - Fedora / RHEL Linux
#   - CentOS Linux
#   - SUSE Linux
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
# Output Functions
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
    error "Security Compliance installation failed."
    echo ""
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

echo ""
echo "============================================================"
echo "       SECURITY COMPLIANCE INSTALLER"
echo "       Version: $VERSION"
echo "============================================================"
echo ""

# ============================================================
# Detect OS
# ============================================================

info "Detecting operating system..."

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
        error "Unsupported operating system: $RAW_OS"
        exit 1
        ;;

esac

# ============================================================
# Detect OS Name and Version
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

    if command -v powershell.exe >/dev/null 2>&1; then

        OS_VERSION="$(
            powershell.exe \
                -NoProfile \
                -NonInteractive \
                -Command \
                "(Get-CimInstance Win32_OperatingSystem).Version" \
                2>/dev/null |
                tr -d '\r'
        )"

    else

        OS_VERSION="Git Bash"

    fi

fi

echo ""
info "Operating System : $OS_NAME"
info "OS Version       : $OS_VERSION"
info "Architecture     : $ARCH"
info "Platform         : $PLATFORM"
echo ""

# ============================================================
# Detect CPU Architecture
# ============================================================

info "Detecting CPU architecture..."

case "$ARCH" in

    x86_64|amd64)
        GITLEAKS_ARCH="x64"
        ;;

    aarch64|arm64)
        GITLEAKS_ARCH="arm64"
        ;;

    *)
        error "Unsupported CPU architecture: $ARCH"
        exit 1
        ;;

esac

success "Architecture detected: $GITLEAKS_ARCH"

# ============================================================
# Linux Distribution Detection
# ============================================================

if [ "$PLATFORM" = "linux" ]; then

    if [ "$LINUX_ID" = "ubuntu" ]; then

        info "Ubuntu detected."
        info "Ubuntu version: $OS_VERSION"

    else

        info "Linux distribution detected: ${LINUX_ID:-Unknown}"

    fi

fi

# ============================================================
# Windows Git Bash Check
# ============================================================

if [ "$PLATFORM" = "windows" ]; then

    info "Windows detected through Git Bash."

    if ! command -v git >/dev/null 2>&1; then

        error "Git was not found."
        error "Git for Windows must be installed first."

        exit 1

    fi

    success "Git is available."

fi

# ============================================================
# Check Git
# ============================================================

info "Checking Git..."

if ! command -v git >/dev/null 2>&1; then

    error "Git is required."
    error "Please install Git and run this installer again."

    exit 1

fi

success "Git detected: $(git --version)"

# ============================================================
# Check curl
# ============================================================

info "Checking curl..."

if ! command -v curl >/dev/null 2>&1; then

    error "curl is required."
    error "Please install curl and run this installer again."

    exit 1

fi

success "curl is available."

# ============================================================
# Create Installation Directories
# ============================================================

info "Creating Security Compliance directories..."

mkdir -p "$BIN_DIR" || fail
mkdir -p "$CONFIG_DIR" || fail
mkdir -p "$HOOK_DIR" || fail

success "Directories created."

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

    if [ -f "$GITLEAKS" ] || [ -x "$GITLEAKS" ]; then

        INSTALLED_VERSION="$(
            "$GITLEAKS" version 2>/dev/null || true
        )"

        if [ "$INSTALLED_VERSION" = "$GITLEAKS_VERSION" ]; then

            success "Gitleaks $GITLEAKS_VERSION is already installed."

            return 0

        fi

        warning "Existing Gitleaks version: $INSTALLED_VERSION"
        info "Installing required version: $GITLEAKS_VERSION"

    else

        info "Gitleaks is not installed."
        info "Installing Gitleaks $GITLEAKS_VERSION."

    fi

    TMP_ROOT="$(mktemp -d)" || fail

    # ========================================================
    # Linux
    # ========================================================

    if [ "$PLATFORM" = "linux" ]; then

        ARCHIVE="gitleaks_${GITLEAKS_VERSION}_linux_${GITLEAKS_ARCH}.tar.gz"

        URL="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${ARCHIVE}"

        info "Downloading Gitleaks..."

        curl \
            --fail \
            --silent \
            --show-error \
            --location \
            --proto '=https' \
            --tlsv1.2 \
            --retry 3 \
            "$URL" \
            -o "$TMP_ROOT/gitleaks.tar.gz" || fail

        tar \
            -xzf "$TMP_ROOT/gitleaks.tar.gz" \
            -C "$TMP_ROOT" || fail

        if [ ! -f "$TMP_ROOT/gitleaks" ]; then

            error "Gitleaks binary was not found."
            fail

        fi

        install \
            -m 0755 \
            "$TMP_ROOT/gitleaks" \
            "$GITLEAKS" || fail

    # ========================================================
    # macOS
    # ========================================================

    elif [ "$PLATFORM" = "darwin" ]; then

        ARCHIVE="gitleaks_${GITLEAKS_VERSION}_darwin_${GITLEAKS_ARCH}.tar.gz"

        URL="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${ARCHIVE}"

        info "Downloading Gitleaks..."

        curl \
            --fail \
            --silent \
            --show-error \
            --location \
            --proto '=https' \
            --tlsv1.2 \
            --retry 3 \
            "$URL" \
            -o "$TMP_ROOT/gitleaks.tar.gz" || fail

        tar \
            -xzf "$TMP_ROOT/gitleaks.tar.gz" \
            -C "$TMP_ROOT" || fail

        if [ ! -f "$TMP_ROOT/gitleaks" ]; then

            error "Gitleaks binary was not found."
            fail

        fi

        install \
            -m 0755 \
            "$TMP_ROOT/gitleaks" \
            "$GITLEAKS" || fail

    # ========================================================
    # Windows / Git Bash
    # ========================================================

    elif [ "$PLATFORM" = "windows" ]; then

        ARCHIVE="gitleaks_${GITLEAKS_VERSION}_windows_${GITLEAKS_ARCH}.zip"

        URL="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${ARCHIVE}"

        info "Downloading Gitleaks..."

        curl \
            --fail \
            --silent \
            --show-error \
            --location \
            --proto '=https' \
            --tlsv1.2 \
            --retry 3 \
            "$URL" \
            -o "$TMP_ROOT/gitleaks.zip" || fail

        if command -v unzip >/dev/null 2>&1; then

            unzip \
                -q \
                "$TMP_ROOT/gitleaks.zip" \
                -d "$TMP_ROOT" || fail

        elif command -v powershell.exe >/dev/null 2>&1; then

            ZIP_WIN="$(cygpath -w "$TMP_ROOT/gitleaks.zip")"
            DEST_WIN="$(cygpath -w "$TMP_ROOT")"

            powershell.exe \
                -NoProfile \
                -NonInteractive \
                -Command \
                "Expand-Archive -Force '$ZIP_WIN' '$DEST_WIN'" \
                || fail

        else

            error "unzip or PowerShell is required."
            fail

        fi

        if [ ! -f "$TMP_ROOT/gitleaks.exe" ]; then

            error "gitleaks.exe was not found."
            fail

        fi

        cp \
            "$TMP_ROOT/gitleaks.exe" \
            "$GITLEAKS" || fail

        chmod +x "$GITLEAKS" 2>/dev/null || true

    fi

    success "Gitleaks $GITLEAKS_VERSION installed."
}

install_gitleaks

# ============================================================
# Verify Gitleaks
# ============================================================

info "Verifying Gitleaks..."

if ! "$GITLEAKS" version >/dev/null 2>&1; then
    fail
fi

INSTALLED_VERSION="$(
    "$GITLEAKS" version 2>/dev/null || true
)"

if [ "$INSTALLED_VERSION" != "$GITLEAKS_VERSION" ]; then

    error "Incorrect Gitleaks version."
    error "Expected: $GITLEAKS_VERSION"
    error "Found: $INSTALLED_VERSION"

    fail

fi

success "Gitleaks version verified: $INSTALLED_VERSION"

# ============================================================
# Create Gitleaks Configuration
# ============================================================

info "Creating Gitleaks configuration..."

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

success "Gitleaks configuration created."

# ============================================================
# Create Global Git Pre-Commit Hook
# ============================================================

info "Creating global Git pre-commit hook..."

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

    echo ""
    echo "Security Compliance: scanner unavailable."
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

mapfile -d '' STAGED_FILES < <(
    git diff --cached \
        --name-only \
        --diff-filter=ACMR \
        -z
)

if [ "${#STAGED_FILES[@]}" -eq 0 ]; then
    exit 0
fi

echo ""
echo "=================================================="
echo "       SECURITY COMPLIANCE SECRET SCAN"
echo "=================================================="
echo ""
echo "Scanning staged changes..."
echo ""

for FILE in "${STAGED_FILES[@]}"; do

    HASH="$(
        printf '%s' "$FILE" |
        sha256sum |
        cut -d' ' -f1
    )"

    TEMP_FILE="$TMP_ROOT/$HASH"

    if ! git show ":$FILE" > "$TEMP_FILE" 2>/dev/null; then

        echo ""
        echo "Unable to read staged file:"
        echo "$FILE"
        echo ""

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
        echo "       SECURITY COMPLIANCE CHECK FAILED"
        echo "=================================================="
        echo ""
        echo "Potential secret detected in:"
        echo ""
        echo "  $FILE"
        echo ""
        echo "$SCAN_OUTPUT"
        echo ""
        echo "Commit blocked."
        echo ""

        FOUND_LEAK=1

    elif [ "$EXIT_CODE" -ne 0 ]; then

        echo ""
        echo "Security Compliance scanner error."
        echo ""
        echo "$SCAN_OUTPUT"
        echo ""
        echo "Commit blocked."
        echo ""

        FOUND_LEAK=1

    fi

done

if [ "$FOUND_LEAK" -ne 0 ]; then
    exit 1
fi

echo ""
echo "=================================================="
echo "       SECURITY COMPLIANCE CHECK PASSED"
echo "       No secrets detected."
echo "=================================================="
echo ""

exit 0
HOOK

chmod 700 "$HOOK_FILE"

success "Global Git pre-commit hook created."

# ============================================================
# Configure Global Git Hooks
# ============================================================

info "Configuring Git global hooks path..."

git config \
    --global \
    core.hooksPath \
    "$HOOK_DIR" || fail

success "Global Git hooks configured."

# ============================================================
# Linux DevOps Tools
# ============================================================

install_linux_tools() {

    if [ "$PLATFORM" != "linux" ]; then
        return 0
    fi

    echo ""
    echo "============================================================"
    echo "       INSTALLING LINUX DEVOPS TOOLS"
    echo "============================================================"
    echo ""

    if ! command -v sudo >/dev/null 2>&1; then
        error "sudo is required."
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
        error "Unsupported Linux package manager."
        fail
    fi

    info "Package manager: $PACKAGE_MANAGER"

    if [ "$PACKAGE_MANAGER" = "apt" ]; then

        sudo apt-get update -y || fail

        sudo apt-get install -y \
            tmate \
            openssh-client \
            openssh-server \
            ansible || fail

    elif [ "$PACKAGE_MANAGER" = "dnf" ]; then

        sudo dnf install -y tmate || warning "tmate installation failed."

        sudo dnf install -y \
            openssh-clients \
            openssh-server || fail

        sudo dnf install -y ansible || warning "Ansible installation failed."

    elif [ "$PACKAGE_MANAGER" = "yum" ]; then

        sudo yum install -y tmate || warning "tmate installation failed."

        sudo yum install -y \
            openssh-clients \
            openssh-server || fail

        sudo yum install -y ansible || warning "Ansible installation failed."

    elif [ "$PACKAGE_MANAGER" = "zypper" ]; then

        sudo zypper --non-interactive install tmate || warning "tmate installation failed."

        sudo zypper --non-interactive install \
            openssh-clients \
            openssh-server || fail

        sudo zypper --non-interactive install ansible || warning "Ansible installation failed."

    fi

    # --------------------------------------------------------
    # Enable SSH server
    # --------------------------------------------------------

    if command -v systemctl >/dev/null 2>&1; then

        if systemctl list-unit-files 2>/dev/null |
            grep -q "^ssh.service"; then

            sudo systemctl enable ssh 2>/dev/null || true
            sudo systemctl start ssh 2>/dev/null || true

        elif systemctl list-unit-files 2>/dev/null |
            grep -q "^sshd.service"; then

            sudo systemctl enable sshd 2>/dev/null || true
            sudo systemctl start sshd 2>/dev/null || true

        fi

    fi

    echo ""
    info "Verifying Linux tools..."

    command -v tmate >/dev/null 2>&1 &&
        success "tmate installed." ||
        warning "tmate not installed."

    command -v ssh >/dev/null 2>&1 &&
        success "OpenSSH client installed." ||
        warning "OpenSSH client not installed."

    command -v sshd >/dev/null 2>&1 &&
        success "OpenSSH server installed." ||
        warning "OpenSSH server not installed."

    command -v ansible >/dev/null 2>&1 &&
        success "Ansible installed." ||
        warning "Ansible not installed."

    success "Linux DevOps tools setup completed."
}

# ============================================================
# macOS DevOps Tools
# ============================================================

install_macos_tools() {

    if [ "$PLATFORM" != "darwin" ]; then
        return 0
    fi

    echo ""
    echo "============================================================"
    echo "       INSTALLING macOS DEVOPS TOOLS"
    echo "============================================================"
    echo ""

    # --------------------------------------------------------
    # Check Homebrew
    # --------------------------------------------------------

    if ! command -v brew >/dev/null 2>&1; then

        warning "Homebrew is not installed."
        info "Installing Homebrew..."

        /bin/bash -c \
            "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
            || fail

        if [ -x "/opt/homebrew/bin/brew" ]; then

            eval "$(/opt/homebrew/bin/brew shellenv)"

        elif [ -x "/usr/local/bin/brew" ]; then

            eval "$(/usr/local/bin/brew shellenv)"

        fi

    fi

    if ! command -v brew >/dev/null 2>&1; then
        error "Homebrew installation failed."
        fail
    fi

    success "Homebrew is available."

    # --------------------------------------------------------
    # tmate
    # --------------------------------------------------------

    info "Installing tmate..."

    brew install tmate || {
        warning "tmate installation failed."
    }

    # --------------------------------------------------------
    # Ansible
    # --------------------------------------------------------

    info "Installing Ansible..."

    brew install ansible || {
        warning "Ansible installation failed."
    }

    # --------------------------------------------------------
    # OpenSSH
    # --------------------------------------------------------

    info "Checking OpenSSH..."

    if command -v ssh >/dev/null 2>&1; then

        success "OpenSSH client is already available."

    else

        info "Installing OpenSSH..."

        brew install openssh || {
            warning "OpenSSH installation failed."
        }

    fi

    # --------------------------------------------------------
    # Verification
    # --------------------------------------------------------

    echo ""
    info "Verifying macOS tools..."

    command -v tmate >/dev/null 2>&1 &&
        success "tmate installed." ||
        warning "tmate not installed."

    command -v ansible >/dev/null 2>&1 &&
        success "Ansible installed." ||
        warning "Ansible not installed."

    command -v ssh >/dev/null 2>&1 &&
        success "OpenSSH client available." ||
        warning "OpenSSH client not available."

    success "macOS DevOps tools setup completed."
}

# ============================================================
# Run OS-Specific DevOps Installation
# ============================================================

install_linux_tools
install_macos_tools

# ============================================================
# Configure Persistent PATH
# ============================================================

info "Configuring Gitleaks PATH..."

if [ "$PLATFORM" = "darwin" ]; then

    PROFILE_FILE="$HOME/.zshrc"

else

    PROFILE_FILE="$HOME/.bashrc"

fi

if [ ! -f "$PROFILE_FILE" ]; then
    touch "$PROFILE_FILE"
fi

if ! grep -Fq '.security-compliance/bin' "$PROFILE_FILE" 2>/dev/null; then

    printf '\n# Security Compliance Gitleaks\n' \
        >> "$PROFILE_FILE"

    printf 'export PATH="$HOME/.security-compliance/bin:$PATH"\n' \
        >> "$PROFILE_FILE"

fi

success "Gitleaks PATH configured."

# ============================================================
# Final Verification
# ============================================================

info "Running final verification..."

if ! "$GITLEAKS" version >/dev/null 2>&1; then
    fail
fi

if [ ! -f "$CONFIG_FILE" ]; then
    error "Gitleaks configuration missing."
    fail
fi

if [ ! -f "$HOOK_FILE" ]; then
    error "Git pre-commit hook missing."
    fail
fi

HOOK_PATH="$(
    git config \
        --global \
        --get core.hooksPath \
        2>/dev/null || true
)"

if [ "$HOOK_PATH" != "$HOOK_DIR" ]; then

    error "Global Git hooks path is incorrect."
    error "Expected: $HOOK_DIR"
    error "Found: $HOOK_PATH"

    fail

fi

# ============================================================
# Cleanup
# ============================================================

cleanup
TMP_ROOT=""

# ============================================================
# Final Output
# ============================================================

echo ""
echo "============================================================"
echo "       SECURITY COMPLIANCE INSTALLATION COMPLETE"
echo "============================================================"
echo ""

success "Installation completed successfully."

echo ""
echo "Operating System : $OS_NAME"
echo "OS Version       : $OS_VERSION"
echo "Architecture     : $ARCH"
echo "Gitleaks Version : $INSTALLED_VERSION"
echo ""
echo "Installation:"
echo "  $INSTALL_ROOT"
echo ""
echo "Configuration:"
echo "  $CONFIG_FILE"
echo ""
echo "Git Hook:"
echo "  $HOOK_FILE"
echo ""
echo "Global Git Hooks:"
echo "  $HOOK_PATH"
echo ""

if [ "$PLATFORM" = "linux" ]; then

    echo "Linux tools:"
    echo "  tmate"
    echo "  Ansible"
    echo "  OpenSSH client"
    echo "  OpenSSH server"

elif [ "$PLATFORM" = "darwin" ]; then

    echo "macOS tools:"
    echo "  tmate"
    echo "  Ansible"
    echo "  OpenSSH client"

fi

echo ""
echo "Git secret scanning is now enabled globally."
echo ""
echo "============================================================"
echo ""

exit 0
