#!/usr/bin/env bash

# ============================================================
# SECURITY COMPLIANCE RELEASE 1
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
# OUTPUT FUNCTIONS
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
# CLEANUP
# ============================================================

cleanup() {
    if [ -n "${TMP_ROOT:-}" ] && [ -d "$TMP_ROOT" ]; then
        rm -rf "$TMP_ROOT"
    fi
}

trap cleanup EXIT

# ============================================================
# HEADER
# ============================================================

echo ""
echo "============================================================"
echo "       SECURITY COMPLIANCE INSTALLER"
echo "       Version: $VERSION"
echo "============================================================"
echo ""

# ============================================================
# DETECT OPERATING SYSTEM
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
# OS INFORMATION
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
# ARCHITECTURE
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
# REQUIRED COMMANDS
# ============================================================

if ! command -v git >/dev/null 2>&1; then
    fail "Git is required. Please install Git first."
fi

if ! command -v curl >/dev/null 2>&1; then
    fail "curl is required. Please install curl first."
fi

success "Git detected: $(git --version)"
success "curl is available."

# ============================================================
# CREATE DIRECTORIES
# ============================================================

info "Creating Security Compliance directories..."

mkdir -p "$BIN_DIR" || fail "Unable to create $BIN_DIR"
mkdir -p "$CONFIG_DIR" || fail "Unable to create $CONFIG_DIR"
mkdir -p "$HOOK_DIR" || fail "Unable to create $HOOK_DIR"

success "Directories created."

# ============================================================
# GITLEAKS PATH
# ============================================================

if [ "$PLATFORM" = "windows" ]; then
    GITLEAKS="$BIN_DIR/gitleaks.exe"
else
    GITLEAKS="$BIN_DIR/gitleaks"
fi

export PATH="$BIN_DIR:$PATH"

# ============================================================
# INSTALL GITLEAKS
# ============================================================

install_gitleaks() {

    if [ -f "$GITLEAKS" ] || [ -x "$GITLEAKS" ]; then

        CURRENT_VERSION="$(
            "$GITLEAKS" version 2>/dev/null || true
        )"

        if [ "$CURRENT_VERSION" = "$GITLEAKS_VERSION" ]; then

            success "Gitleaks $GITLEAKS_VERSION is already installed."
            return 0

        fi

        warning "Existing Gitleaks version: $CURRENT_VERSION"

    fi

    info "Installing Gitleaks $GITLEAKS_VERSION..."

    TMP_ROOT="$(mktemp -d)" || fail "Unable to create temporary directory."

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
            || fail "Unable to download Gitleaks."

        tar \
            -xzf "$TMP_ROOT/gitleaks.tar.gz" \
            -C "$TMP_ROOT" \
            || fail "Unable to extract Gitleaks."

        [ -f "$TMP_ROOT/gitleaks" ] \
            || fail "Gitleaks binary was not found."

        install \
            -m 0755 \
            "$TMP_ROOT/gitleaks" \
            "$GITLEAKS" \
            || fail "Unable to install Gitleaks."

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
            || fail "Unable to download Gitleaks."

        tar \
            -xzf "$TMP_ROOT/gitleaks.tar.gz" \
            -C "$TMP_ROOT" \
            || fail "Unable to extract Gitleaks."

        [ -f "$TMP_ROOT/gitleaks" ] \
            || fail "Gitleaks binary was not found."

        install \
            -m 0755 \
            "$TMP_ROOT/gitleaks" \
            "$GITLEAKS" \
            || fail "Unable to install Gitleaks."

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
            -o "$TMP_ROOT/gitleaks.zip" \
            || fail "Unable to download Gitleaks."

        if command -v unzip >/dev/null 2>&1; then

            unzip \
                -q \
                "$TMP_ROOT/gitleaks.zip" \
                -d "$TMP_ROOT" \
                || fail "Unable to extract Gitleaks."

        elif command -v powershell.exe >/dev/null 2>&1; then

            ZIP_WIN="$(cygpath -w "$TMP_ROOT/gitleaks.zip")"
            DEST_WIN="$(cygpath -w "$TMP_ROOT")"

            powershell.exe \
                -NoProfile \
                -NonInteractive \
                -Command \
                "Expand-Archive -Force '$ZIP_WIN' '$DEST_WIN'" \
                || fail "Unable to extract Gitleaks."

        else

            fail "unzip or PowerShell is required."

        fi

        [ -f "$TMP_ROOT/gitleaks.exe" ] \
            || fail "gitleaks.exe was not found."

        cp "$TMP_ROOT/gitleaks.exe" "$GITLEAKS" \
            || fail "Unable to install Gitleaks."

        chmod +x "$GITLEAKS" 2>/dev/null || true

    fi

    success "Gitleaks installed."

}

install_gitleaks

# ============================================================
# VERIFY GITLEAKS
# ============================================================

info "Verifying Gitleaks..."

INSTALLED_VERSION="$(
    "$GITLEAKS" version 2>/dev/null || true
)"

if [ "$INSTALLED_VERSION" != "$GITLEAKS_VERSION" ]; then

    fail "Gitleaks verification failed. Expected $GITLEAKS_VERSION, found $INSTALLED_VERSION."

fi

success "Gitleaks version verified: $INSTALLED_VERSION"

# ============================================================
# CREATE GITLEAKS CONFIGURATION
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
# CREATE GLOBAL PRE-COMMIT HOOK
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

# ------------------------------------------------------------
# Verify scanner
# ------------------------------------------------------------

if [ ! -f "$GITLEAKS" ] && [ ! -x "$GITLEAKS" ]; then

    echo ""
    echo "=================================================="
    echo "SECURITY COMPLIANCE ERROR"
    echo "=================================================="
    echo "Gitleaks scanner is unavailable."
    echo "Commit blocked."
    echo ""

    exit 1
fi

# ------------------------------------------------------------
# Verify config
# ------------------------------------------------------------

if [ ! -f "$CONFIG" ]; then

    echo ""
    echo "=================================================="
    echo "SECURITY COMPLIANCE ERROR"
    echo "=================================================="
    echo "Gitleaks configuration is unavailable."
    echo "Commit blocked."
    echo ""

    exit 1
fi

# ------------------------------------------------------------
# Get staged files
# ------------------------------------------------------------

STAGED_FILES=()

while IFS= read -r -d '' FILE; do
    STAGED_FILES+=("$FILE")
done < <(
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

TMP_ROOT="$(mktemp -d)"

cleanup() {
    rm -rf "$TMP_ROOT"
}

trap cleanup EXIT

FOUND_LEAK=0

# ------------------------------------------------------------
# Scan each staged file
# ------------------------------------------------------------

for FILE in "${STAGED_FILES[@]}"; do

    HASH="$(
        printf '%s' "$FILE" |
        sha256sum |
        cut -d' ' -f1
    )"

    TEMP_FILE="$TMP_ROOT/$HASH"

    # Get EXACT staged version
    if ! git show ":$FILE" > "$TEMP_FILE" 2>/dev/null; then

        echo "[ERROR] Unable to read staged file:"
        echo "        $FILE"

        FOUND_LEAK=1
        continue

    fi

    # --------------------------------------------------------
    # Skip binary files
    # --------------------------------------------------------

    if file "$TEMP_FILE" 2>/dev/null |
        grep -qi "binary"; then

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
    # Leak found
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
        echo "Commit BLOCKED."
        echo ""

        FOUND_LEAK=1

    # --------------------------------------------------------
    # Scanner error
    # --------------------------------------------------------

    elif [ "$EXIT_CODE" -ne 0 ]; then

        echo ""
        echo "=================================================="
        echo "       SECURITY SCANNER ERROR"
        echo "=================================================="
        echo ""
        echo "$SCAN_OUTPUT"
        echo ""
        echo "Commit BLOCKED."
        echo ""

        FOUND_LEAK=1

    fi

done

# ============================================================
# FINAL RESULT
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
# CONFIGURE GLOBAL GIT HOOK
# ============================================================

info "Configuring Git global hooks path..."

git config \
    --global \
    core.hooksPath \
    "$HOOK_DIR" \
    || fail "Unable to configure Git global hooks path."

success "Global Git hooks configured."

# ============================================================
# LINUX TOOLS
# ============================================================

install_linux_tools() {

    [ "$PLATFORM" = "linux" ] || return 0

    echo ""
    echo "============================================================"
    echo "       INSTALLING LINUX DEVOPS TOOLS"
    echo "============================================================"
    echo ""

    if ! command -v sudo >/dev/null 2>&1; then

        warning "sudo is not available."
        warning "Skipping tmate, Ansible and OpenSSH installation."

        return 0

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

        warning "Unsupported Linux package manager."
        warning "Skipping additional DevOps tools."

        return 0

    fi

    info "Package manager: $PACKAGE_MANAGER"

    # --------------------------------------------------------
    # APT
    # --------------------------------------------------------

    if [ "$PACKAGE_MANAGER" = "apt" ]; then

        info "Updating package information..."

        if ! sudo apt-get update; then

            warning "apt update failed."
            warning "Continuing security installation."

        fi

        info "Installing tmate..."

        sudo apt-get install -y tmate || {
            warning "tmate installation failed."
        }

        info "Installing OpenSSH..."

        sudo apt-get install -y \
            openssh-client \
            openssh-server || {
            warning "OpenSSH installation failed."
        }

        info "Installing Ansible..."

        sudo apt-get install -y ansible || {
            warning "Ansible installation failed."
            warning "This does not affect Gitleaks."
        }

    # --------------------------------------------------------
    # DNF
    # --------------------------------------------------------

    elif [ "$PACKAGE_MANAGER" = "dnf" ]; then

        info "Installing tmate..."

        sudo dnf install -y tmate || {
            warning "tmate installation failed."
        }

        info "Installing OpenSSH..."

        sudo dnf install -y \
            openssh-clients \
            openssh-server || {
            warning "OpenSSH installation failed."
        }

        info "Installing Ansible..."

        sudo dnf install -y ansible || {
            warning "Ansible installation failed."
        }

    # --------------------------------------------------------
    # YUM
    # --------------------------------------------------------

    elif [ "$PACKAGE_MANAGER" = "yum" ]; then

        info "Installing tmate..."

        sudo yum install -y tmate || {
            warning "tmate installation failed."
        }

        info "Installing OpenSSH..."

        sudo yum install -y \
            openssh-clients \
            openssh-server || {
            warning "OpenSSH installation failed."
        }

        info "Installing Ansible..."

        sudo yum install -y ansible || {
            warning "Ansible installation failed."
        }

    # --------------------------------------------------------
    # SUSE
    # --------------------------------------------------------

    elif [ "$PACKAGE_MANAGER" = "zypper" ]; then

        info "Installing tmate..."

        sudo zypper --non-interactive install tmate || {
            warning "tmate installation failed."
        }

        info "Installing OpenSSH..."

        sudo zypper --non-interactive install \
            openssh-clients \
            openssh-server || {
            warning "OpenSSH installation failed."
        }

        info "Installing Ansible..."

        sudo zypper --non-interactive install ansible || {
            warning "Ansible installation failed."
        }

    fi

    # --------------------------------------------------------
    # SSH SERVER
    # --------------------------------------------------------

    if command -v systemctl >/dev/null 2>&1; then

        if systemctl list-unit-files 2>/dev/null |
            grep -q "^ssh.service"; then

            info "Configuring SSH service..."

            sudo systemctl enable ssh 2>/dev/null || true
            sudo systemctl start ssh 2>/dev/null || true

        elif systemctl list-unit-files 2>/dev/null |
            grep -q "^sshd.service"; then

            info "Configuring SSH service..."

            sudo systemctl enable sshd 2>/dev/null || true
            sudo systemctl start sshd 2>/dev/null || true

        fi

    fi

    # --------------------------------------------------------
    # Verification
    # --------------------------------------------------------

    echo ""
    info "Verifying Linux tools..."

    if command -v tmate >/dev/null 2>&1; then
        success "tmate installed."
    else
        warning "tmate is not available."
    fi

    if command -v ssh >/dev/null 2>&1; then
        success "OpenSSH client installed."
    else
        warning "OpenSSH client is not available."
    fi

    if command -v sshd >/dev/null 2>&1; then
        success "OpenSSH server installed."
    else
        warning "OpenSSH server is not available."
    fi

    if command -v ansible >/dev/null 2>&1; then
        success "Ansible installed."
    else
        warning "Ansible is not available."
    fi

}

# ============================================================
# macOS TOOLS
# ============================================================

install_macos_tools() {

    [ "$PLATFORM" = "darwin" ] || return 0

    echo ""
    echo "============================================================"
    echo "       INSTALLING macOS DEVOPS TOOLS"
    echo "============================================================"
    echo ""

    # --------------------------------------------------------
    # Homebrew
    # --------------------------------------------------------

    if ! command -v brew >/dev/null 2>&1; then

        warning "Homebrew is not installed."
        info "Installing Homebrew..."

        /bin/bash -c \
            "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
            || {
                warning "Homebrew installation failed."
                return 0
            }

        if [ -x "/opt/homebrew/bin/brew" ]; then

            eval "$(/opt/homebrew/bin/brew shellenv)"

        elif [ -x "/usr/local/bin/brew" ]; then

            eval "$(/usr/local/bin/brew shellenv)"

        fi

    fi

    if ! command -v brew >/dev/null 2>&1; then

        warning "Homebrew is unavailable."
        warning "Skipping macOS DevOps tools."

        return 0

    fi

    success "Homebrew available."

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

    if command -v ssh >/dev/null 2>&1; then

        success "OpenSSH client already available."

    else

        info "Installing OpenSSH client..."

        brew install openssh || {
            warning "OpenSSH installation failed."
        }

    fi

    # --------------------------------------------------------
    # Verification
    # --------------------------------------------------------

    echo ""
    info "Verifying macOS tools..."

    if command -v tmate >/dev/null 2>&1; then
        success "tmate installed."
    else
        warning "tmate is not available."
    fi

    if command -v ansible >/dev/null 2>&1; then
        success "Ansible installed."
    else
        warning "Ansible is not available."
    fi

    if command -v ssh >/dev/null 2>&1; then
        success "OpenSSH client available."
    else
        warning "OpenSSH client is not available."
    fi

}

# ============================================================
# RUN OS-SPECIFIC INSTALLATION
# ============================================================

install_linux_tools
install_macos_tools

# ============================================================
# PERSISTENT PATH
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

    {
        echo ""
        echo "# Security Compliance Gitleaks"
        echo 'export PATH="$HOME/.security-compliance/bin:$PATH"'
    } >> "$PROFILE_FILE"

fi

success "Gitleaks PATH configured."

# ============================================================
# FINAL SECURITY VERIFICATION
# ============================================================

echo ""
echo "============================================================"
echo "       FINAL SECURITY VERIFICATION"
echo "============================================================"
echo ""

if ! "$GITLEAKS" version >/dev/null 2>&1; then
    fail "Gitleaks final verification failed."
fi

if [ ! -f "$CONFIG_FILE" ]; then
    fail "Gitleaks configuration is missing."
fi

if [ ! -f "$HOOK_FILE" ]; then
    fail "Git pre-commit hook is missing."
fi

HOOK_PATH="$(
    git config \
        --global \
        --get core.hooksPath \
        2>/dev/null || true
)"

if [ "$HOOK_PATH" != "$HOOK_DIR" ]; then

    fail "Git global hooks path is incorrect. Found: $HOOK_PATH"

fi

success "Gitleaks verified."
success "Gitleaks configuration verified."
success "Git pre-commit hook verified."
success "Global Git hooks path verified."

# ============================================================
# FINAL OUTPUT
# ============================================================

echo ""
echo "============================================================"
echo "       SECURITY COMPLIANCE INSTALLATION COMPLETE"
echo "============================================================"
echo ""

success "Security Compliance $VERSION installed successfully."

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

    echo "Linux tools attempted:"
    echo "  - tmate"
    echo "  - Ansible"
    echo "  - OpenSSH client"
    echo "  - OpenSSH server"

elif [ "$PLATFORM" = "darwin" ]; then

    echo "macOS tools attempted:"
    echo "  - tmate"
    echo "  - Ansible"
    echo "  - OpenSSH client"

fi

echo ""
echo "Git secret scanning is now enabled globally."
echo ""
echo "============================================================"
echo ""

exit 0
