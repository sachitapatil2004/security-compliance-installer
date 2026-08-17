#!/usr/bin/env bash

# ============================================================
# Security Compliance Release 1
# Company-wide secret detection
# ============================================================

set -u

VERSION="release1"
GITLEAKS_VERSION="8.30.0"

INSTALL_ROOT="$HOME/.security-compliance"
BIN_DIR="$INSTALL_ROOT/bin"
CONFIG_DIR="$INSTALL_ROOT/config"
HOOK_DIR="$HOME/.git-hooks"

GITLEAKS="$BIN_DIR/gitleaks"
CONFIG_FILE="$CONFIG_DIR/gitleaks.toml"
HOOK_FILE="$HOOK_DIR/pre-commit"

TMP_ROOT=""

cleanup() {
    if [ -n "${TMP_ROOT:-}" ] && [ -d "$TMP_ROOT" ]; then
        rm -rf "$TMP_ROOT"
    fi
}

trap cleanup EXIT

fail() {
    echo ""
    echo "Security Compliance Release 1"
    echo "Setup failed."
    exit 1
}

# ------------------------------------------------------------
# Detect OS
# ------------------------------------------------------------

OS="$(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m 2>/dev/null)"

case "$OS" in
    linux*)
        PLATFORM="linux"
        ;;

    mingw*|msys*|cygwin*)
        PLATFORM="windows"
        ;;

    *)
        echo "Unsupported operating system."
        exit 1
        ;;
esac

# ------------------------------------------------------------
# Detect architecture
# ------------------------------------------------------------

case "$ARCH" in
    x86_64|amd64)
        GITLEAKS_ARCH="x64"
        ;;

    aarch64|arm64)
        GITLEAKS_ARCH="arm64"
        ;;

    *)
        echo "Unsupported architecture."
        exit 1
        ;;
esac

# ------------------------------------------------------------
# Check required commands
# ------------------------------------------------------------

command -v git >/dev/null 2>&1 || {
    echo "Git is required."
    exit 1
}

command -v curl >/dev/null 2>&1 || {
    echo "curl is required."
    exit 1
}

command -v tar >/dev/null 2>&1 || {
    if [ "$PLATFORM" = "linux" ]; then
        echo "tar is required."
        exit 1
    fi
}

# ------------------------------------------------------------
# Create directories
# ------------------------------------------------------------

mkdir -p "$BIN_DIR"
mkdir -p "$CONFIG_DIR"
mkdir -p "$HOOK_DIR"

# ------------------------------------------------------------
# Install Gitleaks
# ------------------------------------------------------------

install_gitleaks() {

    # Already installed and correct version
    if [ -x "$GITLEAKS" ]; then
        INSTALLED_VERSION="$("$GITLEAKS" version 2>/dev/null || true)"

        if [ "$INSTALLED_VERSION" = "$GITLEAKS_VERSION" ]; then
            return 0
        fi
    fi

    TMP_ROOT="$(mktemp -d)"

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
            "$URL" \
            -o "$TMP_ROOT/gitleaks.tar.gz" || fail

        tar -xzf "$TMP_ROOT/gitleaks.tar.gz" \
            -C "$TMP_ROOT" || fail

        if [ ! -f "$TMP_ROOT/gitleaks" ]; then
            fail
        fi

        install -m 0755 "$TMP_ROOT/gitleaks" "$GITLEAKS" || fail

    else

        ARCHIVE="gitleaks_${GITLEAKS_VERSION}_windows_${GITLEAKS_ARCH}.zip"

        URL="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${ARCHIVE}"

        curl \
            --fail \
            --silent \
            --show-error \
            --location \
            --proto '=https' \
            --tlsv1.2 \
            "$URL" \
            -o "$TMP_ROOT/gitleaks.zip" || fail

        if command -v unzip >/dev/null 2>&1; then

            unzip -q "$TMP_ROOT/gitleaks.zip" \
                -d "$TMP_ROOT" || fail

        elif command -v powershell.exe >/dev/null 2>&1; then

            powershell.exe \
                -NoProfile \
                -NonInteractive \
                -Command \
                "Expand-Archive -Force '$TMP_ROOT/gitleaks.zip' '$TMP_ROOT'" \
                >/dev/null 2>&1 || fail

        else
            echo "unzip or PowerShell is required."
            exit 1
        fi

        if [ ! -f "$TMP_ROOT/gitleaks.exe" ]; then
            fail
        fi

        cp "$TMP_ROOT/gitleaks.exe" "$GITLEAKS.exe" || fail
        chmod +x "$GITLEAKS.exe" 2>/dev/null || true

        GITLEAKS="$GITLEAKS.exe"
    fi
}

install_gitleaks

# ------------------------------------------------------------
# Verify Gitleaks
# ------------------------------------------------------------

"$GITLEAKS" version >/dev/null 2>&1 || fail

# ------------------------------------------------------------
# Create company Gitleaks configuration
# ------------------------------------------------------------

cat > "$CONFIG_FILE" <<'EOF'
title = "Security Compliance Release 1"

# Use Gitleaks default rules.
# Company-specific rules can be added here in future releases.

[extend]
useDefault = true
EOF

chmod 600 "$CONFIG_FILE"

# ------------------------------------------------------------
# Create global Git hook
# ------------------------------------------------------------

cat > "$HOOK_FILE" <<'HOOK'
#!/usr/bin/env bash

set -u

SECURITY_ROOT="$HOME/.security-compliance"
GITLEAKS="$SECURITY_ROOT/bin/gitleaks"
CONFIG="$SECURITY_ROOT/config/gitleaks.toml"

if [ ! -x "$GITLEAKS" ]; then
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

# ------------------------------------------------------------
# Get staged files safely
# ------------------------------------------------------------

mapfile -d '' STAGED_FILES < <(
    git diff --cached \
        --name-only \
        --diff-filter=ACMR \
        -z
)

# Nothing staged
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

    TEMP_FILE="$TMP_ROOT/$(printf '%s' "$FILE" | sha256sum | cut -d' ' -f1)"

    # Extract the EXACT staged version.
    if ! git show ":$FILE" > "$TEMP_FILE" 2>/dev/null; then
        echo ""
        echo "Unable to read staged file:"
        echo "$FILE"
        echo ""

        FOUND_LEAK=1
        continue
    fi

    # Scan the staged content.
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

# ------------------------------------------------------------
# Configure Git globally
# ------------------------------------------------------------

git config --global core.hooksPath "$HOOK_DIR" || fail

# ------------------------------------------------------------
# Remove temporary files
# ------------------------------------------------------------

cleanup
TMP_ROOT=""

# ------------------------------------------------------------
# Final verification
# ------------------------------------------------------------

if ! "$GITLEAKS" version >/dev/null 2>&1; then
    fail
fi

if [ ! -x "$HOOK_FILE" ]; then
    fail
fi

HOOK_PATH="$(git config --global --get core.hooksPath 2>/dev/null || true)"

if [ "$HOOK_PATH" != "$HOOK_DIR" ]; then
    fail
fi

# ------------------------------------------------------------
# Final output only
# ------------------------------------------------------------

echo ""
echo "=================================================="
echo "   SECURITY COMPLIANCE RELEASE 1"
echo "=================================================="
echo ""
echo "Security setup completed successfully."
echo ""
echo "Git security scanning is now enabled globally."
echo ""
