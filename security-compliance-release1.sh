# ============================================================
# Linux Security / DevOps Tools Installation
#
# Installs:
#   - tmate
#   - OpenSSH Client
#   - OpenSSH Server
#   - Ansible
#
# Linux only
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

    # --------------------------------------------------------
    # Check sudo
    # --------------------------------------------------------

    if ! command -v sudo >/dev/null 2>&1; then
        error "sudo is required to install Linux packages."
        error "Please install sudo and run the installer again."
        fail
    fi

    # --------------------------------------------------------
    # Detect package manager
    # --------------------------------------------------------

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
        error "Supported package managers: apt, dnf, yum, zypper"
        fail

    fi

    info "Linux distribution: $OS_NAME"
    info "Package manager: $PACKAGE_MANAGER"

    # --------------------------------------------------------
    # Ubuntu / Debian
    # --------------------------------------------------------

    if [ "$PACKAGE_MANAGER" = "apt" ]; then

        info "Updating package information..."

        sudo apt-get update -y || fail

        info "Installing tmate..."

        sudo apt-get install -y tmate || {
            warning "tmate installation failed."
        }

        info "Installing OpenSSH..."

        sudo apt-get install -y \
            openssh-client \
            openssh-server || fail

        info "Installing Ansible..."

        sudo apt-get install -y ansible || {
            warning "Ansible package is not available from the configured repositories."
            warning "Continuing installation."
        }

    # --------------------------------------------------------
    # Fedora / RHEL / Amazon Linux
    # --------------------------------------------------------

    elif [ "$PACKAGE_MANAGER" = "dnf" ]; then

        info "Installing tmate..."

        sudo dnf install -y tmate || {
            warning "tmate installation failed."
        }

        info "Installing OpenSSH..."

        sudo dnf install -y \
            openssh-clients \
            openssh-server || fail

        info "Installing Ansible..."

        sudo dnf install -y ansible || {
            warning "Ansible installation failed."
            warning "Continuing installation."
        }

    # --------------------------------------------------------
    # CentOS / Older RHEL
    # --------------------------------------------------------

    elif [ "$PACKAGE_MANAGER" = "yum" ]; then

        info "Installing tmate..."

        sudo yum install -y tmate || {
            warning "tmate installation failed."
        }

        info "Installing OpenSSH..."

        sudo yum install -y \
            openssh-clients \
            openssh-server || fail

        info "Installing Ansible..."

        sudo yum install -y ansible || {
            warning "Ansible installation failed."
            warning "Continuing installation."
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
            openssh-server || fail

        info "Installing Ansible..."

        sudo zypper --non-interactive install ansible || {
            warning "Ansible installation failed."
            warning "Continuing installation."
        }

    fi

    # --------------------------------------------------------
    # Verify installations
    # --------------------------------------------------------

    echo ""
    info "Verifying Linux tools..."

    if command -v tmate >/dev/null 2>&1; then
        success "tmate: $(tmate -V 2>/dev/null || echo installed)"
    else
        warning "tmate was not installed."
    fi

    if command -v ssh >/dev/null 2>&1; then
        success "OpenSSH client: $(ssh -V 2>&1 | head -n 1)"
    else
        warning "OpenSSH client was not installed."
    fi

    if command -v ansible >/dev/null 2>&1; then
        success "Ansible: $(ansible --version 2>/dev/null | head -n 1)"
    else
        warning "Ansible was not installed."
    fi

    echo ""

    # --------------------------------------------------------
    # Enable SSH service if available
    # --------------------------------------------------------

    if command -v systemctl >/dev/null 2>&1; then

        if systemctl list-unit-files 2>/dev/null |
            grep -q "^ssh.service"; then

            info "Enabling SSH service..."

            sudo systemctl enable ssh 2>/dev/null || true
            sudo systemctl start ssh 2>/dev/null || true

            success "SSH service configured."

        elif systemctl list-unit-files 2>/dev/null |
            grep -q "^sshd.service"; then

            info "Enabling SSH service..."

            sudo systemctl enable sshd 2>/dev/null || true
            sudo systemctl start sshd 2>/dev/null || true

            success "SSH service configured."

        fi

    fi

    echo ""
    success "Linux DevOps tools setup completed."
    echo ""
}
