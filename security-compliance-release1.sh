#!/usr/bin/env bash

# ============================================================
# Security Compliance Release 1
# Company-wide Secret Detection Installer
#
# Supported:
#   - Ubuntu Linux
#   - Other Linux distributions
#   - macOS Intel
#   - macOS Apple Silicon
#   - Windows through Git Bash
#
# Gitleaks Version:
#   8.30.0
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
    error "Security Compliance $VERSION installation failed."
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
# Detect Operating System
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

# ------------------------------------------------------------
# Linux
# ------------------------------------------------------------

if [ "$PLATFORM" = "linux" ]; then

    if [ -f /etc/os-release ]; then

        . /etc/os-release

        OS_NAME="${NAME:-Linux}"
        OS_VERSION="${VERSION_ID:-Unknown}"

    else

        OS_NAME="Linux"
        OS_VERSION="$(uname -r)"

    fi

fi

# ------------------------------------------------------------
# macOS
# ------------------------------------------------------------

if [ "$PLATFORM" = "darwin" ]; then

    OS_NAME="macOS"

    OS_VERSION="$(
        sw_vers -productVersion 2>/dev/null || echo "Unknown"
    )"

fi

# ------------------------------------------------------------
# Windows / Git Bash
# ------------------------------------------------------------

if [ "$PLATFORM" = "windows" ]; then

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
# Linux Distribution Detection
# ============================================================

if [ "$PLATFORM" = "linux" ]; then

    if [ "${ID:-}" = "ubuntu" ]; then

        info "Ubuntu detected."
        info "Ubuntu Version: $OS_VERSION"

        case "$OS_VERSION" in

            20.04|22.04|24.04|26.04)
                success "Supported Ubuntu version detected."
                ;;

            *)
                warning "Ubuntu $OS_VERSION detected."
                warning "This version has not been explicitly tested."
                warning "Continuing installation."
                ;;

        esac

    else

        warning "Ubuntu was not detected."
        warning "Linux distribution: ${ID:-Unknown}"
        warning "Continuing with generic Linux installation."

    fi

fi

# ============================================================
# macOS Version Detection
# ============================================================

if [ "$PLATFORM" = "darwin" ]; then

    info "macOS detected."

    MAC_MAJOR="$(
        echo "$OS_VERSION" |
        cut -d'.' -f1
    )"

    if [ -n "$MAC_MAJOR" ] &&
       [ "$MAC_MAJOR" -ge 12 ] 2>/dev/null; then

        success "Supported macOS version detected."

    else

        warning "Older macOS version detected: $OS_VERSION"
        warning "Continuing installation."

    fi

fi

# ============================================================
# Windows Detection
# ============================================================

if [ "$PLATFORM" = "windows" ]; then

    info "Windows detected through Git Bash."

    if command -v git >/dev/null 2>&1; then

        success "Git is available."

    else

        error "Git was not found."
        error "Install Git for Windows first."
        exit 1

    fi

fi

# ============================================================
# CPU Architecture Detection
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
        error "Unsupported architecture: $ARCH"
        exit 1
        ;;

esac

success "Architecture detected: $GITLEAKS_ARCH"

# ============================================================
# Check Git
# ============================================================

info "Checking Git installation..."

if ! command -v git >/dev/null 2>&1; then

    error "Git is required but was not found."
    error "Please install Git and run the installer again."

    exit 1

fi

GIT_VERSION="$(git --version 2>/dev/null || true)"

success "Git detected: $GIT_VERSION"

# ============================================================
# Check curl
# ============================================================

info "Checking curl..."

if ! command -v curl >/dev/null 2>&1; then

    error "curl is required."
    error "Please install curl and run the installer again."

    exit 1

fi

success "curl is available."

# ============================================================
# Check Required Tools
# ============================================================

if [ "$PLATFORM" = "linux" ] || [ "$PLATFORM" = "darwin" ]; then

    if ! command -v tar >/dev/null 2>&1; then

        error "tar is required."
        exit 1

    fi

fi

if [ "$PLATFORM" = "windows" ]; then

    if ! command -v unzip >/dev/null 2>&1 &&
       ! command -v powershell.exe >/dev/null 2>&1; then

        error "unzip or PowerShell is required."
        exit 1

    fi

fi

# ============================================================
# Create Directories
# ============================================================

info "Creating Security Compliance directories..."

mkdir -p "$BIN_DIR" || fail
mkdir -p "$CONFIG_DIR" || fail
mkdir -p "$HOOK_DIR" || fail

success "Directories created."

# ============================================================
# Set Gitleaks Path
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
    # Check Existing Installation
    # --------------------------------------------------------

    if [ -f "$GITLEAKS" ] || [ -x "$GITLEAKS" ]; then

        INSTALLED_VERSION="$(
            "$GITLEAKS" version 2>/dev/null || true
        )"

        if [ "$INSTALLED_VERSION" = "$GITLEAKS_VERSION" ]; then

            success "Gitleaks $GITLEAKS_VERSION is already installed."

            return 0

        fi

        warning "Different Gitleaks version detected."
        info "Required version: $GITLEAKS_VERSION"
        info "Installing required version."

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

        info "Downloading $ARCHIVE"

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

        info "Extracting Gitleaks."

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

        info "Downloading $ARCHIVE"

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

        info "Extracting Gitleaks."

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

        info "Downloading $ARCHIVE"

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

        info "Extracting Gitleaks."

        if command -v unzip >/dev/null 2>&1; then

            unzip \
                -q \
                "$TMP_ROOT/gitleaks.zip" \
                -d "$TMP_ROOT" || fail

        elif command -v powershell.exe >/dev/null 2>&1; then

            ZIP_WIN="$(
                cygpath -w "$TMP_ROOT/gitleaks.zip"
            )"

            DEST_WIN="$(
                cygpath -w "$TMP_ROOT"
            )"

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

info "Verifying Gitleaks installation..."

if ! "$GITLEAKS" version >/dev/null 2>&1; then

    error "Gitleaks installation verification failed."
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

# ============================================================
# Company-specific rules
# ============================================================

[[rules]]
id = "office-hardcoded-password"
description = "Potential hardcoded password"
regex = '''(?i)(password|passwd|pwd)\s*[:=]\s*["']([^"']{8,})["']'''
secretGroup = 2
keywords = ["password", "passwd", "pwd"]

[[rules]]
id = "aws-access-key"
description = "Potential AWS Access Key ID"
regex = '''AKIA[0-9A-Z]{16}'''
keywords = ["AKIA"]
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

# ============================================================
# Detect Gitleaks executable
# ============================================================

if [ -f "$SECURITY_ROOT/bin/gitleaks.exe" ]; then

    GITLEAKS="$SECURITY_ROOT/bin/gitleaks.exe"

else

    GITLEAKS="$SECURITY_ROOT/bin/gitleaks"

fi

CONFIG="$SECURITY_ROOT/config/gitleaks.toml"

# ============================================================
# Verify Gitleaks
# ============================================================

if [ ! -f "$GITLEAKS" ] && [ ! -x "$GITLEAKS" ]; then

    echo ""
    echo "Security Compliance: scanner unavailable."
    echo "Commit blocked."
    echo ""

    exit 1

fi

# ============================================================
# Verify Configuration
# ============================================================

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

# ============================================================
# Get Staged Files
# ============================================================

git diff --cached \
    --name-only \
    --diff-filter=ACMR \
    -z |
while IFS= read -r -d '' FILE; do

    HASH="$(
        printf '%s' "$FILE" |
        sha256sum |
        cut -d' ' -f1
    )"

    TEMP_FILE="$TMP_ROOT/$HASH"

    # --------------------------------------------------------
    # Extract exact staged version
    # --------------------------------------------------------

    if ! git show ":$FILE" > "$TEMP_FILE" 2>/dev/null; then

        echo ""
        echo "Unable to read staged file:"
        echo "$FILE"
        echo ""

        FOUND_LEAK=1

        continue

    fi

    # --------------------------------------------------------
    # Run Gitleaks
    # --------------------------------------------------------

    SCAN_OUTPUT="$(
        "$GITLEAKS" dir "$TEMP_FILE" \
            --config "$CONFIG" \
            --redact \
            --no-banner \
            --exit-code 1 \
            2>&1
    )"

    EXIT_CODE=$?

    # --------------------------------------------------------
    # Secret Found
    # --------------------------------------------------------

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

    # --------------------------------------------------------
    # Scanner Error
    # --------------------------------------------------------

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

# ============================================================
# Final Result
# ============================================================

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
# Configure Git Global Hooks Path
# ============================================================

info "Configuring Git global hooks path..."

git config \
    --global \
    core.hooksPath \
    "$HOOK_DIR" || fail

success "Git global hooks path configured."

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

if ! grep -Fq "$BIN_DIR" "$PROFILE_FILE" 2>/dev/null; then

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

    error "Configuration verification failed."
    fail

fi

if [ ! -f "$HOOK_FILE" ]; then

    error "Git hook verification failed."
    fail

fi

HOOK_PATH="$(
    git config \
        --global \
        --get core.hooksPath \
        2>/dev/null || true
)"

if [ "$HOOK_PATH" != "$HOOK_DIR" ]; then

    error "Git global hooks path verification failed."
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
echo "       SECURITY COMPLIANCE RELEASE 1"
echo "============================================================"
echo ""

success "Security setup completed successfully."

echo ""
echo "Operating System : $OS_NAME"
echo "OS Version       : $OS_VERSION"
echo "Architecture     : $ARCH"
echo "Gitleaks Version  : $INSTALLED_VERSION"
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
echo "Git security scanning is now enabled globally."
echo ""
echo "============================================================"
echo ""

exit 0
