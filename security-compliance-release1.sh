#!/usr/bin/env bash

set -u

GITLEAKS_VERSION="8.30.0"

INSTALL_ROOT="$HOME/.security-compliance"
BIN_DIR="$INSTALL_ROOT/bin"
CONFIG_DIR="$INSTALL_ROOT/config"
HOOK_DIR="$HOME/.git-hooks"

mkdir -p "$BIN_DIR" "$CONFIG_DIR" "$HOOK_DIR" || {
    echo "ERROR: Unable to create installation directories."
    exit 1
}

# ============================================================
# Detect OS
# ============================================================

OS="$(uname -s 2>/dev/null)"
ARCH="$(uname -m 2>/dev/null)"

case "$OS" in
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
        echo "ERROR: Unsupported operating system."
        exit 1
        ;;
esac

case "$ARCH" in
    x86_64|amd64)
        GL_ARCH="x64"
        ;;
    arm64|aarch64)
        GL_ARCH="arm64"
        ;;
    *)
        echo "ERROR: Unsupported architecture."
        exit 1
        ;;
esac

# ============================================================
# Check dependencies
# ============================================================

if ! command -v git >/dev/null 2>&1; then
    echo "ERROR: Git is not installed."
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "ERROR: curl is not installed."
    exit 1
fi

# ============================================================
# Gitleaks path
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

    CURRENT=""

    if [ -x "$GITLEAKS" ]; then
        CURRENT="$("$GITLEAKS" version 2>/dev/null || true)"
    fi

    if [ "$CURRENT" = "$GITLEAKS_VERSION" ]; then
        return 0
    fi

    TMP_DIR="$(mktemp -d)" || return 1

    # --------------------------------------------------------
    # Linux
    # --------------------------------------------------------

    if [ "$PLATFORM" = "linux" ]; then

        FILE="gitleaks_${GITLEAKS_VERSION}_linux_${GL_ARCH}.tar.gz"

        URL="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${FILE}"

        if ! curl -fsSL \
            --retry 3 \
            "$URL" \
            -o "$TMP_DIR/gitleaks.tar.gz" \
            >/dev/null 2>&1; then

            rm -rf "$TMP_DIR"
            return 1
        fi

        if ! tar -xzf \
            "$TMP_DIR/gitleaks.tar.gz" \
            -C "$TMP_DIR" \
            >/dev/null 2>&1; then

            rm -rf "$TMP_DIR"
            return 1
        fi

        if [ ! -f "$TMP_DIR/gitleaks" ]; then
            rm -rf "$TMP_DIR"
            return 1
        fi

        if ! install \
            -m 0755 \
            "$TMP_DIR/gitleaks" \
            "$GITLEAKS" \
            >/dev/null 2>&1; then

            rm -rf "$TMP_DIR"
            return 1
        fi

    # --------------------------------------------------------
    # macOS
    # --------------------------------------------------------

    elif [ "$PLATFORM" = "darwin" ]; then

        FILE="gitleaks_${GITLEAKS_VERSION}_darwin_${GL_ARCH}.tar.gz"

        URL="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${FILE}"

        if ! curl -fsSL \
            --retry 3 \
            "$URL" \
            -o "$TMP_DIR/gitleaks.tar.gz" \
            >/dev/null 2>&1; then

            rm -rf "$TMP_DIR"
            return 1
        fi

        if ! tar -xzf \
            "$TMP_DIR/gitleaks.tar.gz" \
            -C "$TMP_DIR" \
            >/dev/null 2>&1; then

            rm -rf "$TMP_DIR"
            return 1
        fi

        if [ ! -f "$TMP_DIR/gitleaks" ]; then
            rm -rf "$TMP_DIR"
            return 1
        fi

        if ! install \
            -m 0755 \
            "$TMP_DIR/gitleaks" \
            "$GITLEAKS" \
            >/dev/null 2>&1; then

            rm -rf "$TMP_DIR"
            return 1
        fi

    # --------------------------------------------------------
    # Windows Git Bash
    # --------------------------------------------------------

    elif [ "$PLATFORM" = "windows" ]; then

        FILE="gitleaks_${GITLEAKS_VERSION}_windows_${GL_ARCH}.zip"

        URL="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${FILE}"

        if ! curl -fsSL \
            --retry 3 \
            "$URL" \
            -o "$TMP_DIR/gitleaks.zip" \
            >/dev/null 2>&1; then

            rm -rf "$TMP_DIR"
            return 1
        fi

        if command -v unzip >/dev/null 2>&1; then

            unzip -q \
                "$TMP_DIR/gitleaks.zip" \
                -d "$TMP_DIR" \
                >/dev/null 2>&1 || {
                    rm -rf "$TMP_DIR"
                    return 1
                }

        elif command -v powershell.exe >/dev/null 2>&1; then

            ZIP_PATH="$(cygpath -w "$TMP_DIR/gitleaks.zip")"
            DEST_PATH="$(cygpath -w "$TMP_DIR")"

            powershell.exe \
                -NoProfile \
                -NonInteractive \
                -Command \
                "Expand-Archive -Force '$ZIP_PATH' '$DEST_PATH'" \
                >/dev/null 2>&1 || {
                    rm -rf "$TMP_DIR"
                    return 1
                }

        else
            rm -rf "$TMP_DIR"
            return 1
        fi

        if [ ! -f "$TMP_DIR/gitleaks.exe" ]; then
            rm -rf "$TMP_DIR"
            return 1
        fi

        cp \
            "$TMP_DIR/gitleaks.exe" \
            "$GITLEAKS" \
            >/dev/null 2>&1 || {
                rm -rf "$TMP_DIR"
                return 1
            }

        chmod +x "$GITLEAKS" 2>/dev/null || true
    fi

    rm -rf "$TMP_DIR"

    return 0
}

# ============================================================
# Install Gitleaks
# ============================================================

if ! install_gitleaks; then
    echo "ERROR: Gitleaks installation failed."
    exit 1
fi

# ============================================================
# Verify Gitleaks
# ============================================================

VERSION_CHECK="$(
    "$GITLEAKS" version 2>/dev/null || true
)"

if [ "$VERSION_CHECK" != "$GITLEAKS_VERSION" ]; then
    echo "ERROR: Gitleaks verification failed."
    exit 1
fi

# ============================================================
# Create Gitleaks configuration
# ============================================================

cat > "$CONFIG_DIR/gitleaks.toml" <<'EOF'
title = "Security Compliance"

[extend]
useDefault = true
EOF

chmod 600 "$CONFIG_DIR/gitleaks.toml" 2>/dev/null || true

# ============================================================
# Create Global Git Pre-Commit Hook
# ============================================================

cat > "$HOOK_DIR/pre-commit" <<'EOF'
#!/usr/bin/env bash

GITLEAKS="$HOME/.security-compliance/bin/gitleaks"
CONFIG="$HOME/.security-compliance/config/gitleaks.toml"

if [ ! -x "$GITLEAKS" ]; then
    exit 1
fi

FILES=$(git diff --cached --name-only --diff-filter=ACMR)

[ -z "$FILES" ] && exit 0

for FILE in $FILES; do

    TMP=$(mktemp)

    if ! git show ":$FILE" > "$TMP" 2>/dev/null; then
        rm -f "$TMP"
        exit 1
    fi

    "$GITLEAKS" dir "$TMP" \
        --config "$CONFIG" \
        --redact \
        --no-banner \
        --exit-code 1 \
        >/dev/null 2>&1

    RESULT=$?

    rm -f "$TMP"

    if [ "$RESULT" -eq 1 ]; then
        echo ""
        echo "ERROR: Secret detected in $FILE"
        echo "Commit blocked."
        echo ""
        exit 1
    fi

    if [ "$RESULT" -gt 1 ]; then
        echo ""
        echo "ERROR: Gitleaks scan failed."
        echo "Commit blocked."
        echo ""
        exit 1
    fi

done

exit 0
EOF

chmod 700 "$HOOK_DIR/pre-commit"

# ============================================================
# Configure Git
# ============================================================

if ! git config --global core.hooksPath "$HOOK_DIR" >/dev/null 2>&1; then
    echo "ERROR: Unable to configure Git hooks."
    exit 1
fi

# ============================================================
# Linux tools
# ============================================================

if [ "$PLATFORM" = "linux" ]; then

    if command -v sudo >/dev/null 2>&1; then

        if command -v apt-get >/dev/null 2>&1; then

            sudo apt-get update -qq >/dev/null 2>&1 || true

            sudo apt-get install -y -qq \
                tmate \
                openssh-client \
                openssh-server \
                ansible \
                >/dev/null 2>&1 || true

        elif command -v dnf >/dev/null 2>&1; then

            sudo dnf install -y -q \
                tmate \
                openssh-clients \
                openssh-server \
                ansible \
                >/dev/null 2>&1 || true

        elif command -v yum >/dev/null 2>&1; then

            sudo yum install -y -q \
                tmate \
                openssh-clients \
                openssh-server \
                ansible \
                >/dev/null 2>&1 || true

        elif command -v zypper >/dev/null 2>&1; then

            sudo zypper --non-interactive install \
                tmate \
                openssh-clients \
                openssh-server \
                ansible \
                >/dev/null 2>&1 || true

        fi

    fi

fi

# ============================================================
# macOS tools
# ============================================================

if [ "$PLATFORM" = "darwin" ]; then

    if command -v brew >/dev/null 2>&1; then

        brew install tmate >/dev/null 2>&1 || true
        brew install ansible >/dev/null 2>&1 || true
        brew install openssh >/dev/null 2>&1 || true

    fi

fi

# ============================================================
# Add Gitleaks to PATH
# ============================================================

if [ "$PLATFORM" = "darwin" ]; then
    PROFILE="$HOME/.zshrc"
else
    PROFILE="$HOME/.bashrc"
fi

touch "$PROFILE" 2>/dev/null || true

if ! grep -Fq ".security-compliance/bin" "$PROFILE" 2>/dev/null; then
    echo 'export PATH="$HOME/.security-compliance/bin:$PATH"' >> "$PROFILE"
fi

# ============================================================
# FINAL OUTPUT
# ============================================================

echo "SUCCESS: Gitleaks installed"

exit 0
