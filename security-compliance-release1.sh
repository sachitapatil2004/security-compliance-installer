#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# COMPLETE SECRET SECURITY SETUP
# ============================================================
#
# Security layers:
#
# 1. Betterleaks
#       - Local secret detection
#
# 2. detect-secrets
#       - Baseline management
#       - New secret detection
#
# 3. Pre-commit
#       - Blocks commits containing secrets
#
# 4. TruffleHog
#       - Deep repository scanning
#       - Credential verification
#       - GitHub Actions
#
# 5. GitHub Secret Scanning
#       - Server-side repository protection
#
# 6. GitHub Push Protection
#       - Prevents supported secrets from being pushed
#
# Supported source types:
#
# Python, Java, JavaScript, TypeScript, TSX, JSX,
# Node.js, PHP, C, C++, Go, Ruby, Shell, YAML, JSON,
# Dockerfiles, .env, Terraform, Kubernetes manifests, etc.
#
# ============================================================

set -o pipefail

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

INSTALL_DIR="/usr/local/bin"

PROJECT_DIR="$(pwd)"

PRE_COMMIT_CONFIG=".pre-commit-config.yaml"
SECRETS_BASELINE=".secrets.baseline"

BETTERLEAKS_VERSION="v1.7.2"

GITHUB_WORKFLOW_DIR=".github/workflows"
GITHUB_WORKFLOW_FILE="${GITHUB_WORKFLOW_DIR}/secret-security.yml"

LOG_FILE="/tmp/secret-security-setup.log"

# ------------------------------------------------------------
# Colors
# ------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ------------------------------------------------------------
# Logging functions
# ------------------------------------------------------------

log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ------------------------------------------------------------
# Error handler
# ------------------------------------------------------------

trap 'error "Setup failed at line $LINENO. Check $LOG_FILE for details."' ERR

exec > >(tee -a "$LOG_FILE") 2>&1

# ============================================================
# START
# ============================================================

echo ""
echo "============================================================"
echo "        COMPLETE SECRET SECURITY SETUP"
echo "============================================================"
echo ""

log "Project directory: $PROJECT_DIR"

# ============================================================
# 1. Check Linux
# ============================================================

if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    error "This version of the script supports Linux/Ubuntu."
    error "Use the Windows PowerShell version for Windows machines."
    exit 1
fi

success "Linux detected."

# ============================================================
# 2. Check architecture
# ============================================================

RAW_ARCH="$(uname -m)"

case "$RAW_ARCH" in
    x86_64)
        ARCH="amd64"
        ;;
    aarch64|arm64)
        ARCH="arm64"
        ;;
    *)
        error "Unsupported architecture: $RAW_ARCH"
        exit 1
        ;;
esac

log "Architecture: $ARCH"

# ============================================================
# 3. Check sudo
# ============================================================

if ! command -v sudo >/dev/null 2>&1; then
    error "sudo is required."
    exit 1
fi

success "sudo available."

# ============================================================
# 4. Install system dependencies
# ============================================================

log "Installing required packages..."

sudo apt-get update

sudo apt-get install -y \
    curl \
    wget \
    git \
    python3 \
    python3-pip \
    python3-venv \
    ca-certificates \
    jq \
    unzip

success "System dependencies installed."

# ============================================================
# 5. Install GitHub CLI
# ============================================================

echo ""
echo "------------------------------------------------------------"
echo "GitHub CLI"
echo "------------------------------------------------------------"

if command -v gh >/dev/null 2>&1; then

    success "GitHub CLI already installed."
    gh --version | head -1

else

    log "Installing GitHub CLI..."

    type -p curl >/dev/null || sudo apt-get install -y curl

    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
        status=none

    sudo chmod go+r \
        /usr/share/keyrings/githubcli-archive-keyring.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null

    sudo apt-get update

    sudo apt-get install -y gh

    success "GitHub CLI installed."

fi

# ============================================================
# 6. Install pre-commit
# ============================================================

echo ""
echo "------------------------------------------------------------"
echo "Pre-commit"
echo "------------------------------------------------------------"

if command -v pre-commit >/dev/null 2>&1; then

    success "pre-commit already installed."
    pre-commit --version

else

    log "Installing pre-commit..."

    python3 -m pip install \
        --user \
        --break-system-packages \
        pre-commit 2>/dev/null || \
    python3 -m pip install \
        --user \
        pre-commit

    export PATH="$HOME/.local/bin:$PATH"

    if ! command -v pre-commit >/dev/null 2>&1; then
        error "pre-commit installation failed."
        exit 1
    fi

    success "pre-commit installed."

fi

# ============================================================
# 7. Install Betterleaks
# ============================================================

echo ""
echo "------------------------------------------------------------"
echo "Betterleaks"
echo "------------------------------------------------------------"

if command -v betterleaks >/dev/null 2>&1; then

    success "Betterleaks already installed."
    betterleaks --version || true

else

    TEMP_DIR="$(mktemp -d)"

    log "Downloading Betterleaks ${BETTERLEAKS_VERSION}..."

    # GitHub release API
    RELEASE_URL="https://api.github.com/repos/betterleaks/betterleaks/releases/tags/${BETTERLEAKS_VERSION}"

    ASSET_URL="$(
        curl -fsSL "$RELEASE_URL" |
        jq -r --arg arch "$ARCH" '
            .assets[]
            | select(.name | test("linux_" + $arch + "\\.tar\\.gz$"))
            | .browser_download_url
        ' |
        head -1
    )"

    if [[ -z "$ASSET_URL" || "$ASSET_URL" == "null" ]]; then
        error "Could not find Betterleaks Linux $ARCH release asset."
        error "Check: https://github.com/betterleaks/betterleaks/releases"
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    curl -fL "$ASSET_URL" \
        -o "$TEMP_DIR/betterleaks.tar.gz"

    tar -xzf "$TEMP_DIR/betterleaks.tar.gz" \
        -C "$TEMP_DIR"

    BETTERLEAKS_BINARY="$(find "$TEMP_DIR" -type f -name betterleaks | head -1)"

    if [[ -z "$BETTERLEAKS_BINARY" ]]; then
        error "Betterleaks binary not found in release."
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    sudo install -m 0755 \
        "$BETTERLEAKS_BINARY" \
        "$INSTALL_DIR/betterleaks"

    rm -rf "$TEMP_DIR"

    success "Betterleaks installed."

fi

betterleaks --version || true

# ============================================================
# 8. Install TruffleHog
# ============================================================

echo ""
echo "------------------------------------------------------------"
echo "TruffleHog"
echo "------------------------------------------------------------"

if command -v trufflehog >/dev/null 2>&1; then

    success "TruffleHog already installed."
    trufflehog --version || true

else

    log "Installing TruffleHog..."

    curl -sSfL \
        https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh \
        | sudo sh -s -- -b "$INSTALL_DIR"

    success "TruffleHog installed."

fi

trufflehog --version || true

# ============================================================
# 9. Install detect-secrets
# ============================================================

echo ""
echo "------------------------------------------------------------"
echo "detect-secrets"
echo "------------------------------------------------------------"

if command -v detect-secrets >/dev/null 2>&1; then

    success "detect-secrets already installed."
    detect-secrets --version

else

    log "Installing detect-secrets..."

    python3 -m pip install \
        --user \
        --break-system-packages \
        detect-secrets 2>/dev/null || \
    python3 -m pip install \
        --user \
        detect-secrets

    export PATH="$HOME/.local/bin:$PATH"

    if ! command -v detect-secrets >/dev/null 2>&1; then
        error "detect-secrets installation failed."
        exit 1
    fi

    success "detect-secrets installed."

fi

detect-secrets --version

# ============================================================
# 10. Check Git repository
# ============================================================

echo ""
echo "------------------------------------------------------------"
echo "Git Repository"
echo "------------------------------------------------------------"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then

    error "This script must be executed inside a Git repository."

    echo ""
    echo "Example:"
    echo "  cd /path/to/repository"
    echo "  ./setup-secret-security.sh"

    exit 1
fi

success "Git repository detected."

# ============================================================
# 11. Create detect-secrets baseline
# ============================================================

echo ""
echo "------------------------------------------------------------"
echo "detect-secrets Baseline"
echo "------------------------------------------------------------"

if [[ -f "$SECRETS_BASELINE" ]]; then

    success "$SECRETS_BASELINE already exists."

else

    log "Creating detect-secrets baseline..."

    detect-secrets scan > "$SECRETS_BASELINE"

    success "Created $SECRETS_BASELINE."

fi

# ============================================================
# 12. Create .pre-commit-config.yaml
# ============================================================

echo ""
echo "------------------------------------------------------------"
echo "Pre-commit Configuration"
echo "------------------------------------------------------------"

if [[ -f "$PRE_COMMIT_CONFIG" ]]; then

    warning "$PRE_COMMIT_CONFIG already exists."
    warning "Existing configuration will NOT be overwritten."

else

cat > "$PRE_COMMIT_CONFIG" <<'EOF'
repos:

  # ==========================================================
  # detect-secrets
  # ==========================================================

  - repo: https://github.com/Yelp/detect-secrets
    rev: v1.5.0
    hooks:
      - id: detect-secrets
        args:
          - --baseline
          - .secrets.baseline

  # ==========================================================
  # Betterleaks
  # ==========================================================

  - repo: local
    hooks:

      - id: betterleaks
        name: Betterleaks Secret Scan
        entry: betterleaks
        language: system
        pass_filenames: false
        stages:
          - pre-commit

EOF

success "Created $PRE_COMMIT_CONFIG."

fi

# ============================================================
# 13. Install pre-commit hook
# ============================================================

echo ""
echo "------------------------------------------------------------"
echo "Installing Git Hook"
echo "------------------------------------------------------------"

pre-commit install

success "Pre-commit hook installed."

# ============================================================
# 14. Create GitHub Actions workflow
# ============================================================

echo ""
echo "------------------------------------------------------------"
echo "GitHub Actions"
echo "------------------------------------------------------------"

mkdir -p "$GITHUB_WORKFLOW_DIR"

if [[ -f "$GITHUB_WORKFLOW_FILE" ]]; then

    warning "$GITHUB_WORKFLOW_FILE already exists."
    warning "Existing workflow will NOT be overwritten."

else

cat > "$GITHUB_WORKFLOW_FILE" <<'EOF'
name: Secret Security Scan

on:

  pull_request:

  push:
    branches:
      - main
      - master
      - staging

permissions:
  contents: read

jobs:

  trufflehog:
    name: TruffleHog Secret Scan

    runs-on: ubuntu-latest

    steps:

      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: TruffleHog scan
        uses: trufflesecurity/trufflehog@main
        with:
          path: ./
          extra_args: --results=verified,unknown --fail
EOF

success "Created GitHub Actions workflow."

fi

# ============================================================
# 15. Detect GitHub repository
# ============================================================

echo ""
echo "------------------------------------------------------------"
echo "GitHub Repository"
echo "------------------------------------------------------------"

REMOTE_URL="$(git remote get-url origin 2>/dev/null || true)"

if [[ -z "$REMOTE_URL" ]]; then

    warning "No origin remote found."
    warning "GitHub Secret Scanning cannot be configured automatically."

else

    success "Git remote found: $REMOTE_URL"

fi

# ============================================================
# 16. GitHub Authentication
# ============================================================

if [[ -n "$REMOTE_URL" ]]; then

    if gh auth status >/dev/null 2>&1; then

        success "GitHub CLI is authenticated."

        # ----------------------------------------------------
        # Get repository
        # ----------------------------------------------------

        GH_REPO="$(gh repo view --json nameWithOwner \
            -q '.nameWithOwner' 2>/dev/null || true)"

        if [[ -n "$GH_REPO" ]]; then

            success "GitHub repository: $GH_REPO"

            # ------------------------------------------------
            # Check repository permissions
            # ------------------------------------------------

            PERMISSION="$(
                gh api \
                    "repos/$GH_REPO" \
                    --jq '.permissions.admin // false' \
                    2>/dev/null || echo "false"
            )"

            if [[ "$PERMISSION" == "true" ]]; then

                success "GitHub repository admin permission available."

                # ====================================================
                # 17. Enable GitHub Secret Scanning
                # ====================================================

                log "Enabling GitHub Secret Scanning..."

                if gh api \
                    --method PATCH \
                    "repos/$GH_REPO" \
                    -f 'security_and_analysis[secret_scanning][status]=enabled' \
                    >/dev/null 2>&1; then

                    success "GitHub Secret Scanning enabled."

                else

                    warning "Could not enable Secret Scanning automatically."
                    warning "This may depend on your GitHub plan or repository permissions."

                fi

                # ====================================================
                # 18. Enable Push Protection
                # ====================================================

                log "Enabling GitHub Push Protection..."

                if gh api \
                    --method PATCH \
                    "repos/$GH_REPO" \
                    -f 'security_and_analysis[secret_scanning_push_protection][status]=enabled' \
                    >/dev/null 2>&1; then

                    success "GitHub Push Protection enabled."

                else

                    warning "Could not enable Push Protection automatically."
                    warning "Check repository security settings and GitHub plan."

                fi

            else

                warning "GitHub admin permission is not available."
                warning "Secret Scanning and Push Protection cannot be enabled automatically."

            fi

        else

            warning "Could not determine GitHub repository."

        fi

    else

        warning "GitHub CLI is not authenticated."

        echo ""
        echo "Run:"
        echo ""
        echo "    gh auth login"
        echo ""
        echo "Then run this script again to enable:"
        echo ""
        echo "    GitHub Secret Scanning"
        echo "    GitHub Push Protection"
        echo ""

    fi

fi

# ============================================================
# 19. Run Betterleaks scan
# ============================================================

echo ""
echo "------------------------------------------------------------"
echo "Betterleaks Initial Scan"
echo "------------------------------------------------------------"

if betterleaks dir .; then

    success "Betterleaks scan completed successfully."

else

    warning "Betterleaks detected potential secrets."
    warning "Review the findings before continuing."

fi

# ============================================================
# 20. Run detect-secrets scan
# ============================================================

echo ""
echo "------------------------------------------------------------"
echo "detect-secrets Initial Scan"
echo "------------------------------------------------------------"

if detect-secrets scan \
    --baseline "$SECRETS_BASELINE" \
    >/tmp/detect-secrets-output.txt 2>&1; then

    success "detect-secrets scan completed."

else

    warning "detect-secrets reported findings."
    warning "Review the findings."

    cat /tmp/detect-secrets-output.txt || true

fi

# ============================================================
# 21. Test TruffleHog
# ============================================================

echo ""
echo "------------------------------------------------------------"
echo "TruffleHog Initial Scan"
echo "------------------------------------------------------------"

if trufflehog filesystem . \
    --results=verified,unknown \
    >/tmp/trufflehog-output.txt 2>&1; then

    success "TruffleHog scan completed."

else

    warning "TruffleHog reported findings or scan returned non-zero."

    cat /tmp/trufflehog-output.txt || true

fi

# ============================================================
# 22. Pre-commit test
# ============================================================

echo ""
echo "------------------------------------------------------------"
echo "Pre-commit Test"
echo "------------------------------------------------------------"

if pre-commit run --all-files; then

    success "Pre-commit security checks passed."

else

    warning "Pre-commit detected one or more findings."

fi

# ============================================================
# 23. Final summary
# ============================================================

echo ""
echo "============================================================"
echo "           SECURITY SETUP COMPLETED"
echo "============================================================"

echo ""
echo "Installed security components:"
echo ""

echo "1. Betterleaks"
betterleaks --version || true

echo ""
echo "2. TruffleHog"
trufflehog --version || true

echo ""
echo "3. detect-secrets"
detect-secrets --version || true

echo ""
echo "4. pre-commit"
pre-commit --version || true

echo ""
echo "5. GitHub Secret Scanning"
echo "   Configured through GitHub API when permissions allow."

echo ""
echo "6. GitHub Push Protection"
echo "   Configured through GitHub API when permissions allow."

echo ""
echo "Files created:"
echo ""
echo "   $PRE_COMMIT_CONFIG"
echo "   $SECRETS_BASELINE"
echo "   $GITHUB_WORKFLOW_FILE"

echo ""
echo "Git hook:"
echo ""
echo "   .git/hooks/pre-commit"

echo ""
echo "============================================================"
echo "Security layers:"
echo "============================================================"
echo ""
echo "Developer Laptop"
echo "       ↓"
echo "Betterleaks"
echo "       ↓"
echo "detect-secrets"
echo "       ↓"
echo "pre-commit"
echo "       ↓"
echo "Git"
echo "       ↓"
echo "GitHub Push Protection"
echo "       ↓"
echo "GitHub Secret Scanning"
echo "       ↓"
echo "GitHub Actions"
echo "       ↓"
echo "TruffleHog"
echo ""

echo "============================================================"
echo "Setup log:"
echo "  $LOG_FILE"
echo "============================================================"
