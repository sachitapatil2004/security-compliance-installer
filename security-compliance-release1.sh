#!/usr/bin/env bash

set -u

GITLEAKS_VERSION="8.30.0"

BASE_DIR="$HOME/.security-compliance"
BIN_DIR="$BASE_DIR/bin"
CONFIG_DIR="$BASE_DIR/config"
HOOK_DIR="$HOME/.git-hooks"

GITLEAKS="$BIN_DIR/gitleaks"
CONFIG_FILE="$CONFIG_DIR/gitleaks.toml"
HOOK_FILE="$HOOK_DIR/pre-commit"

TMP_DIR=""

cleanup() {
    if [ -n "${TMP_DIR:-}" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}

trap cleanup EXIT

fail() {
    exit 1
}

OS="$(uname -s 2>/dev/null || true)"
ARCH="$(uname -m 2>/dev/null || true)"

case "$OS" in
    Linux)
        PLATFORM="linux"
        ;;

    Darwin)
        PLATFORM="darwin"
        ;;

    MINGW*|MSYS*|CYGWIN*)
        PLATFORM="windows"
        ;;

    *)
        exit 1
        ;;
esac

case "$ARCH" in
    x86_64|amd64)
        GITLEAKS_ARCH="x64"
        ;;

    aarch64|arm64)
        GITLEAKS_ARCH="arm64"
        ;;

    *)
        exit 1
        ;;
esac

command -v git >/dev/null 2>&1 || exit 1

mkdir -p "$BIN_DIR" "$CONFIG_DIR" "$HOOK_DIR"

export PATH="$BIN_DIR:$PATH"

TMP_DIR="$(mktemp -d)"

install_linux_or_macos() {

    case "$PLATFORM" in
        linux)
            ARCHIVE="gitleaks_${GITLEAKS_VERSION}_linux_${GITLEAKS_ARCH}.tar.gz"
            ;;

        darwin)
            ARCHIVE="gitleaks_${GITLEAKS_VERSION}_darwin_${GITLEAKS_ARCH}.tar.gz"
            ;;
    esac

    URL="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${ARCHIVE}"

    if [ -x "$GITLEAKS" ]; then
        CURRENT="$("$GITLEAKS" version 2>/dev/null || true)"

        if [ "$CURRENT" = "$GITLEAKS_VERSION" ]; then
            return 0
        fi
    fi

    if command -v curl >/dev/null 2>&1; then

        curl -fsSL \
            --retry 3 \
            --connect-timeout 10 \
            "$URL" \
            -o "$TMP_DIR/gitleaks.tar.gz" \
            >/dev/null 2>&1 || fail

    elif command -v wget >/dev/null 2>&1; then

        wget -q \
            "$URL" \
            -O "$TMP_DIR/gitleaks.tar.gz" \
            >/dev/null 2>&1 || fail

    else
        fail
    fi

    tar -xzf "$TMP_DIR/gitleaks.tar.gz" \
        -C "$TMP_DIR" \
        >/dev/null 2>&1 || fail

    [ -f "$TMP_DIR/gitleaks" ] || fail

    install -m 0755 \
        "$TMP_DIR/gitleaks" \
        "$GITLEAKS" \
        >/dev/null 2>&1 || fail
}

install_windows_gitbash() {

    GITLEAKS="$BIN_DIR/gitleaks.exe"

    ARCHIVE="gitleaks_${GITLEAKS_VERSION}_windows_${GITLEAKS_ARCH}.zip"

    URL="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${ARCHIVE}"

    if [ -f "$GITLEAKS" ]; then
        return 0
    fi

    if command -v curl >/dev/null 2>&1; then

        curl -fsSL \
            --retry 3 \
            "$URL" \
            -o "$TMP_DIR/gitleaks.zip" \
            >/dev/null 2>&1 || fail

    elif command -v wget >/dev/null 2>&1; then

        wget -q \
            "$URL" \
            -O "$TMP_DIR/gitleaks.zip" \
            >/dev/null 2>&1 || fail

    else
        fail
    fi

    if command -v unzip >/dev/null 2>&1; then

        unzip -q \
            "$TMP_DIR/gitleaks.zip" \
            -d "$TMP_DIR" \
            >/dev/null 2>&1 || fail

    else
        fail
    fi

    [ -f "$TMP_DIR/gitleaks.exe" ] || fail

    cp "$TMP_DIR/gitleaks.exe" "$GITLEAKS" || fail
    chmod +x "$GITLEAKS" 2>/dev/null || true
}

case "$PLATFORM" in
    linux|darwin)
        install_linux_or_macos
        ;;

    windows)
        install_windows_gitbash
        ;;
esac

"$GITLEAKS" version >/dev/null 2>&1 || fail

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

cat > "$HOOK_FILE" <<'EOF'
#!/usr/bin/env bash

set -u

ROOT="$HOME/.security-compliance"
GITLEAKS="$ROOT/bin/gitleaks"
CONFIG="$ROOT/config/gitleaks.toml"

[ -x "$GITLEAKS" ] || exit 1
[ -f "$CONFIG" ] || exit 1

TMP_ROOT="$(mktemp -d)"

cleanup_hook() {
    rm -rf "$TMP_ROOT"
}

trap cleanup_hook EXIT

FOUND_LEAK=0

if git rev-parse --git-dir >/dev/null 2>&1; then

    mapfile -d '' FILES < <(
        git diff --cached --name-only --diff-filter=ACMR -z
    )

    for FILE in "${FILES[@]}"; do

        git cat-file -e ":$FILE" 2>/dev/null || continue

        HASH="$(printf '%s' "$FILE" | sha256sum | cut -d' ' -f1)"
        TEMP_FILE="$TMP_ROOT/$HASH"

        git show ":$FILE" > "$TEMP_FILE" 2>/dev/null || {
            FOUND_LEAK=1
            continue
        }

        OUTPUT="$(
            "$GITLEAKS" dir "$TEMP_FILE" \
                --config "$CONFIG" \
                --redact \
                --no-banner \
                --exit-code 1 \
                2>&1
        )"

        RC=$?

        if [ "$RC" -ne 0 ]; then
            echo ""
            echo "=================================================="
            echo "       SECURITY COMPLIANCE CHECK FAILED"
            echo "=================================================="
            echo ""
            echo "Potential secret detected in:"
            echo ""
            echo "  $FILE"
            echo ""
            echo "$OUTPUT"
            echo ""
            echo "Commit blocked."
            echo ""

            FOUND_LEAK=1
        fi
    done
fi

[ "$FOUND_LEAK" -eq 0 ] || exit 1

exit 0
EOF

chmod 700 "$HOOK_FILE"

git config --global core.hooksPath "$HOOK_DIR" >/dev/null 2>&1 || fail

for RC in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$RC" ] && ! grep -Fq "$BIN_DIR" "$RC" 2>/dev/null; then
        printf '\nexport PATH="$HOME/.security-compliance/bin:$PATH"\n' >> "$RC"
    fi
done

"$GITLEAKS" version >/dev/null 2>&1 || fail

git config --global --get core.hooksPath \
    | grep -Fxq "$HOOK_DIR" || fail

[ -x "$HOOK_FILE" ] || fail

cleanup
TMP_DIR=""

exit 0
