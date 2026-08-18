# ============================================================
# Security Compliance Release 1
# Windows Bootstrap Installer
#
# Purpose:
#   1. Detect Windows version
#   2. Detect CPU architecture
#   3. Check Git for Windows / Git Bash
#   4. Install Git for Windows if missing
#   5. Locate bash.exe
#   6. Download security-compliance-release1.sh
#   7. Execute the .sh through Git Bash
#   8. Verify installation
#
# Windows:
#   - Windows 10
#   - Windows 11
#   - x64
#   - ARM64
#
# The .sh installer handles:
#   - Linux
#   - macOS
#   - Windows through Git Bash
#   - Gitleaks
#   - Git global pre-commit hook
#
# Linux-only tools such as:
#   - tmate
#   - OpenSSH server
#   - Ansible
#
# are NOT installed on Windows.
# ============================================================

$ErrorActionPreference = "Stop"

$VERSION = "release1"
$GITLEAKS_VERSION = "8.30.0"

$SCRIPT_URL = "https://raw.githubusercontent.com/sachitapatil2004/security-compliance-installer/main/security-compliance-release1.sh"

$INSTALL_ROOT = Join-Path $env:USERPROFILE ".security-compliance-bootstrap"

$SCRIPT_FILE = Join-Path `
    $INSTALL_ROOT `
    "security-compliance-release1.sh"

$GitInstaller = Join-Path `
    $INSTALL_ROOT `
    "git-installer.exe"

# ============================================================
# Functions
# ============================================================

function Write-Info {
    param([string]$Message)

    Write-Host "[INFO] $Message"
}

function Write-Success {
    param([string]$Message)

    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-WarningMessage {
    param([string]$Message)

    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-ErrorMessage {
    param([string]$Message)

    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Fail-Installation {
    param([string]$Message)

    Write-Host ""
    Write-ErrorMessage $Message
    Write-Host ""
    Write-Host "Security Compliance installation failed." -ForegroundColor Red
    Write-Host ""

    exit 1
}

# ============================================================
# Header
# ============================================================

Write-Host ""

Write-Host "============================================================"
Write-Host "       SECURITY COMPLIANCE INSTALLER"
Write-Host "       Windows Bootstrap - $VERSION"
Write-Host "============================================================"

Write-Host ""

# ============================================================
# Check Windows
# ============================================================

Write-Info "Checking operating system..."

if ($env:OS -ne "Windows_NT") {

    Fail-Installation `
        "This installer must be executed on Windows."

}

try {

    $OSInfo = Get-CimInstance Win32_OperatingSystem

}
catch {

    Fail-Installation `
        "Unable to detect Windows operating system information."

}

$OSVersion = $OSInfo.Version
$OSCaption = $OSInfo.Caption

Write-Info "Operating System : $OSCaption"
Write-Info "Windows Version  : $OSVersion"

# ============================================================
# Detect Windows Version
# ============================================================

if ($OSCaption -match "Windows 10") {

    Write-Success "Windows 10 detected."

}
elseif ($OSCaption -match "Windows 11") {

    Write-Success "Windows 11 detected."

}
else {

    Write-WarningMessage `
        "This Windows version has not been explicitly tested."

    Write-WarningMessage `
        "Continuing installation."

}

# ============================================================
# Detect Architecture
# ============================================================

Write-Info "Detecting CPU architecture..."

$Architecture = $env:PROCESSOR_ARCHITECTURE

switch ($Architecture) {

    "AMD64" {

        $DetectedArchitecture = "x64"

    }

    "ARM64" {

        $DetectedArchitecture = "arm64"

    }

    default {

        Fail-Installation `
            "Unsupported Windows architecture: $Architecture"

    }

}

Write-Success `
    "Architecture detected: $DetectedArchitecture"

# ============================================================
# Create Bootstrap Directory
# ============================================================

Write-Info "Creating bootstrap directory..."

if (-not (Test-Path $INSTALL_ROOT)) {

    New-Item `
        -ItemType Directory `
        -Path $INSTALL_ROOT `
        -Force |
        Out-Null

}

Write-Success "Bootstrap directory ready."

# ============================================================
# Find Git Bash
# ============================================================

function Find-GitBash {

    $PossiblePaths = @(

        "$env:ProgramFiles\Git\bin\bash.exe"

        "$env:ProgramFiles\Git\usr\bin\bash.exe"

        "${env:ProgramFiles(x86)}\Git\bin\bash.exe"

        "${env:ProgramFiles(x86)}\Git\usr\bin\bash.exe"

        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"

        "$env:LOCALAPPDATA\Programs\Git\usr\bin\bash.exe"

    )

    foreach ($Path in $PossiblePaths) {

        if ($Path -and (Test-Path $Path)) {

            return $Path

        }

    }

    # --------------------------------------------------------
    # Check PATH
    # --------------------------------------------------------

    $GitBashCommand = Get-Command `
        bash.exe `
        -ErrorAction SilentlyContinue

    if ($GitBashCommand) {

        return $GitBashCommand.Source

    }

    return $null
}

# ============================================================
# Check Git
# ============================================================

Write-Info `
    "Checking whether Git for Windows is installed..."

$GitCommand = Get-Command `
    git.exe `
    -ErrorAction SilentlyContinue

if ($GitCommand) {

    Write-Success "Git for Windows detected."

    Write-Info "Git path:"
    Write-Host "  $($GitCommand.Source)"

}
else {

    Write-WarningMessage `
        "Git for Windows is not installed."

    Write-Info `
        "Git for Windows will be installed automatically."

}

# ============================================================
# Check Git Bash
# ============================================================

$GitBash = Find-GitBash

# ============================================================
# Install Git for Windows if required
# ============================================================

if (-not $GitBash) {

    Write-WarningMessage `
        "Git Bash was not found."

    Write-Info `
        "Downloading Git for Windows..."

    # --------------------------------------------------------
    # Official Git for Windows release
    #
    # This is the GitHub release page used to obtain Git.
    # --------------------------------------------------------

    $GitDownloadURL = `
        "https://github.com/git-for-windows/git/releases/latest/download/Git-64-bit.exe"

    try {

        Invoke-WebRequest `
            -Uri $GitDownloadURL `
            -OutFile $GitInstaller `
            -UseBasicParsing

    }
    catch {

        Fail-Installation `
            "Unable to download Git for Windows. $($_.Exception.Message)"

    }

    if (-not (Test-Path $GitInstaller)) {

        Fail-Installation `
            "Git for Windows installer was not downloaded."

    }

    Write-Success `
        "Git for Windows installer downloaded."

    # --------------------------------------------------------
    # Install Git
    # --------------------------------------------------------

    Write-Info `
        "Installing Git for Windows..."

    Write-Info `
        "Please wait..."

    try {

        $Process = Start-Process `
            -FilePath $GitInstaller `
            -ArgumentList @(
                "/VERYSILENT"
                "/NORESTART"
                "/NOCANCEL"
                "/SP-"
            ) `
            -Wait `
            -PassThru

    }
    catch {

        Fail-Installation `
            "Unable to start Git for Windows installer. $($_.Exception.Message)"

    }

    if ($Process.ExitCode -ne 0) {

        Fail-Installation `
            "Git for Windows installation failed. Exit code: $($Process.ExitCode)"

    }

    Write-Success `
        "Git for Windows installed."

    # --------------------------------------------------------
    # Refresh PATH
    # --------------------------------------------------------

    Write-Info `
        "Refreshing Windows PATH..."

    $MachinePath = `
        [System.Environment]::GetEnvironmentVariable(
            "Path",
            "Machine"
        )

    $UserPath = `
        [System.Environment]::GetEnvironmentVariable(
            "Path",
            "User"
        )

    $env:Path = `
        "$MachinePath;$UserPath"

    Start-Sleep -Seconds 2

    # --------------------------------------------------------
    # Find Git Bash again
    # --------------------------------------------------------

    Write-Info `
        "Searching for Git Bash..."

    $GitBash = Find-GitBash

}

# ============================================================
# Verify Git Bash
# ============================================================

if (-not $GitBash) {

    Fail-Installation `
        "Git Bash was installed but bash.exe could not be found."

}

Write-Success `
    "Git Bash detected."

Write-Info "Git Bash path:"
Write-Host "  $GitBash"

# ============================================================
# Verify Git Bash version
# ============================================================

Write-Info `
    "Verifying Git Bash..."

try {

    $BashVersion = & $GitBash --version 2>&1

}
catch {

    Fail-Installation `
        "Git Bash verification failed."

}

if (-not $BashVersion) {

    Fail-Installation `
        "Git Bash did not return a version."

}

Write-Success `
    "Git Bash verification successful."

Write-Host $BashVersion

# ============================================================
# Verify Git
# ============================================================

Write-Info "Verifying Git..."

try {

    $GitVersion = & git.exe --version 2>&1

}
catch {

    Fail-Installation `
        "Git verification failed."

}

if (-not $GitVersion) {

    Fail-Installation `
        "Git did not return a version."

}

Write-Success "Git detected: $GitVersion"

# ============================================================
# Download Security Compliance Installer
# ============================================================

Write-Info `
    "Downloading Security Compliance installer..."

try {

    Invoke-WebRequest `
        -Uri $SCRIPT_URL `
        -OutFile $SCRIPT_FILE `
        -UseBasicParsing

}
catch {

    Fail-Installation `
        "Unable to download security-compliance-release1.sh. $($_.Exception.Message)"

}

# ============================================================
# Verify downloaded file
# ============================================================

if (-not (Test-Path $SCRIPT_FILE)) {

    Fail-Installation `
        "Security Compliance shell script was not downloaded."

}

$ScriptSize = `
    (Get-Item $SCRIPT_FILE).Length

if ($ScriptSize -lt 1000) {

    Fail-Installation `
        "Downloaded installer appears to be invalid."

}

Write-Success `
    "Security Compliance installer downloaded."

Write-Info `
    "Installer size: $ScriptSize bytes"

# ============================================================
# Convert Windows Path to Git Bash Path
# ============================================================

Write-Info `
    "Preparing Git Bash execution path..."

$GitBashScriptPath = `
    $SCRIPT_FILE.Replace("\", "/")

if ($GitBashScriptPath -match "^([A-Za-z]):/(.*)$") {

    $Drive = `
        $Matches[1].ToLower()

    $RemainingPath = `
        $Matches[2]

    $GitBashScriptPath = `
        "/$Drive/$RemainingPath"

}

Write-Info `
    "Git Bash script path: $GitBashScriptPath"

# ============================================================
# Execute Security Compliance Installer
# ============================================================

Write-Host ""

Write-Host "============================================================"
Write-Host "       RUNNING SECURITY COMPLIANCE INSTALLER"
Write-Host "============================================================"

Write-Host ""

try {

    $Process = Start-Process `
        -FilePath $GitBash `
        -ArgumentList @(
            "--login"
            "-c"
            "bash `"$GitBashScriptPath`""
        ) `
        -Wait `
        -PassThru `
        -NoNewWindow

}
catch {

    Fail-Installation `
        "Unable to execute Security Compliance installer. $($_.Exception.Message)"

}

# ============================================================
# Check Shell Installer Result
# ============================================================

if ($Process.ExitCode -ne 0) {

    Write-Host ""

    Write-ErrorMessage `
        "Security Compliance installer returned an error."

    Write-ErrorMessage `
        "Exit code: $($Process.ExitCode)"

    Write-Host ""

    exit $Process.ExitCode

}

# ============================================================
# Verify Gitleaks Installation
# ============================================================

Write-Info `
    "Verifying Gitleaks installation..."

$GitleaksPath = `
    Join-Path `
        $env:USERPROFILE `
        ".security-compliance/bin/gitleaks.exe"

if (-not (Test-Path $GitleaksPath)) {

    Fail-Installation `
        "Gitleaks executable was not found."

}

try {

    $GitleaksVersion = `
        & $GitleaksPath version 2>&1

}
catch {

    Fail-Installation `
        "Gitleaks verification failed."

}

Write-Success `
    "Gitleaks detected: $GitleaksVersion"

# ============================================================
# Verify Global Git Hook
# ============================================================

Write-Info `
    "Verifying global Git hook configuration..."

$GitHooksPath = `
    & git.exe config --global --get core.hooksPath 2>$null

if (-not $GitHooksPath) {

    Fail-Installation `
        "Git global hooks path was not configured."

}

Write-Success `
    "Global Git hooks path: $GitHooksPath"

# ============================================================
# Final Success
# ============================================================

Write-Host ""

Write-Host "============================================================"
Write-Host "       SECURITY COMPLIANCE INSTALLATION COMPLETE"
Write-Host "============================================================"

Write-Host ""

Write-Success `
    "Windows operating system detected."

Write-Success `
    "Git for Windows / Git Bash is available."

Write-Success `
    "Security Compliance installer executed successfully."

Write-Success `
    "Gitleaks $GITLEAKS_VERSION is installed."

Write-Success `
    "Global Git security scanning is configured."

Write-Host ""

Write-Host "Installation location:"
Write-Host "  $env:USERPROFILE\.security-compliance"

Write-Host ""

Write-Host "Global Git hooks:"
Write-Host "  $GitHooksPath"

Write-Host ""

Write-Host "You can now use Git normally."

Write-Host ""

Write-Host "============================================================"
Write-Host ""

# ============================================================
# Cleanup Bootstrap Files
# ============================================================

try {

    if (Test-Path $GitInstaller) {

        Remove-Item `
            $GitInstaller `
            -Force `
            -ErrorAction SilentlyContinue

    }

    if (Test-Path $SCRIPT_FILE) {

        Remove-Item `
            $SCRIPT_FILE `
            -Force `
            -ErrorAction SilentlyContinue

    }

}
catch {

    # Cleanup failure must not make successful installation fail.

}

exit 0
