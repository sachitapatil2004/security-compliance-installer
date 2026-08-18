# ============================================================
# Security Compliance Release 1
# Windows Bootstrap Installer
#
# Purpose:
#   1. Check whether Git for Windows / Git Bash exists
#   2. Install Git for Windows if missing
#   3. Locate bash.exe
#   4. Download security-compliance-release1.sh
#   5. Execute the Linux/macOS/Windows-compatible installer
#   6. Verify success/failure
#
# Supported:
#   Windows 10
#   Windows 11
#   x64
#   ARM64
# ============================================================

$ErrorActionPreference = "Stop"

$VERSION = "release1"
$GITLEAKS_VERSION = "8.30.0"

$SCRIPT_URL = "https://raw.githubusercontent.com/sachitapatil2004/security-compliance-installer/main/security-compliance-release1.sh"

$INSTALL_ROOT = Join-Path $env:USERPROFILE ".security-compliance-bootstrap"
$SCRIPT_FILE = Join-Path $INSTALL_ROOT "security-compliance-release1.sh"

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

if (-not $IsWindows -and $env:OS -ne "Windows_NT") {
    Fail-Installation "This installer must be executed on Windows PowerShell."
}

$OSInfo = Get-CimInstance Win32_OperatingSystem

$OSVersion = $OSInfo.Version
$OSCaption = $OSInfo.Caption

Write-Info "Operating System : $OSCaption"
Write-Info "Windows Version  : $OSVersion"

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
        Fail-Installation "Unsupported Windows architecture: $Architecture"
    }
}

Write-Success "Architecture detected: $DetectedArchitecture"

# ============================================================
# Create Bootstrap Directory
# ============================================================

Write-Info "Creating bootstrap directory..."

if (-not (Test-Path $INSTALL_ROOT)) {
    New-Item -ItemType Directory -Path $INSTALL_ROOT -Force | Out-Null
}

Write-Success "Bootstrap directory ready."

# ============================================================
# Find Git Bash
# ============================================================

function Find-GitBash {

    $PossiblePaths = @(
        "$env:ProgramFiles\Git\bin\bash.exe",
        "$env:ProgramFiles\Git\usr\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\usr\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\usr\bin\bash.exe"
    )

    foreach ($Path in $PossiblePaths) {

        if ($Path -and (Test-Path $Path)) {
            return $Path
        }
    }

    # Check PATH
    $GitBashCommand = Get-Command bash.exe -ErrorAction SilentlyContinue

    if ($GitBashCommand) {
        return $GitBashCommand.Source
    }

    return $null
}

# ============================================================
# Check Git Bash
# ============================================================

Write-Info "Checking whether Git for Windows / Git Bash is installed..."

$GitBash = Find-GitBash

if ($GitBash) {

    Write-Success "Git Bash detected."

    Write-Info "Git Bash path:"
    Write-Host "  $GitBash"

}
else {

    Write-WarningMessage "Git Bash is not installed."
    Write-Info "Git for Windows will be installed automatically."

    # ========================================================
    # Download Git for Windows
    # ========================================================

    $GitInstaller = Join-Path $INSTALL_ROOT "git-installer.exe"

    # Official Git for Windows download
    $GitDownloadURL = "https://github.com/git-for-windows/git/releases/latest/download/Git-2.51.0-64-bit.exe"

    Write-Info "Downloading Git for Windows..."

    try {

        Invoke-WebRequest `
            -Uri $GitDownloadURL `
            -OutFile $GitInstaller `
            -UseBasicParsing

    }
    catch {

        Fail-Installation "Unable to download Git for Windows. $($_.Exception.Message)"
    }

    if (-not (Test-Path $GitInstaller)) {
        Fail-Installation "Git for Windows installer was not downloaded."
    }

    Write-Success "Git for Windows downloaded."

    # ========================================================
    # Install Git for Windows
    # ========================================================

    Write-Info "Installing Git for Windows..."
    Write-Info "Please wait..."

    try {

        $Process = Start-Process `
            -FilePath $GitInstaller `
            -ArgumentList "/VERYSILENT", "/NORESTART", "/NOCANCEL", "/SP-" `
            -Wait `
            -PassThru

    }
    catch {

        Fail-Installation "Unable to start Git for Windows installer. $($_.Exception.Message)"
    }

    if ($Process.ExitCode -ne 0) {

        Fail-Installation "Git for Windows installation failed. Exit code: $($Process.ExitCode)"
    }

    Write-Success "Git for Windows installed."

    # ========================================================
    # Search Git Bash Again
    # ========================================================

    Write-Info "Searching for Git Bash..."

    Start-Sleep -Seconds 2

    $GitBash = Find-GitBash

    if (-not $GitBash) {

        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable(
            "Path",
            "Machine"
        ) + ";" +
        [System.Environment]::GetEnvironmentVariable(
            "Path",
            "User"
        )

        $GitBash = Find-GitBash
    }

    if (-not $GitBash) {

        Fail-Installation "Git Bash was installed but bash.exe could not be found."
    }

    Write-Success "Git Bash is now available."

    Write-Info "Git Bash path:"
    Write-Host "  $GitBash"
}

# ============================================================
# Verify Git Bash
# ============================================================

Write-Info "Verifying Git Bash..."

try {

    $BashVersion = & $GitBash --version 2>&1

}
catch {

    Fail-Installation "Git Bash verification failed."
}

if (-not $BashVersion) {

    Fail-Installation "Git Bash did not return a version."
}

Write-Success "Git Bash verification successful."

# ============================================================
# Download Security Compliance Shell Script
# ============================================================

Write-Info "Downloading Security Compliance installer..."

try {

    Invoke-WebRequest `
        -Uri $SCRIPT_URL `
        -OutFile $SCRIPT_FILE `
        -UseBasicParsing

}
catch {

    Fail-Installation "Unable to download security-compliance-release1.sh. $($_.Exception.Message)"
}

if (-not (Test-Path $SCRIPT_FILE)) {

    Fail-Installation "Security Compliance shell script was not downloaded."
}

Write-Success "Security Compliance installer downloaded."

# ============================================================
# Verify downloaded script is not empty
# ============================================================

$ScriptSize = (Get-Item $SCRIPT_FILE).Length

if ($ScriptSize -lt 100) {

    Fail-Installation "Downloaded security-compliance-release1.sh appears to be invalid."
}

Write-Success "Security Compliance installer verified."

# ============================================================
# Convert Windows path to Git Bash path
# ============================================================

Write-Info "Preparing Git Bash execution..."

$GitBashScriptPath = $SCRIPT_FILE.Replace("\", "/")

# Convert:
# C:\Users\User\...
#
# to:
# /c/Users/User/...

if ($GitBashScriptPath -match "^([A-Za-z]):/(.*)$") {

    $Drive = $Matches[1].ToLower()
    $RemainingPath = $Matches[2]

    $GitBashScriptPath = "/$Drive/$RemainingPath"
}

Write-Info "Executing Security Compliance installer through Git Bash..."

Write-Host ""

# ============================================================
# Execute .sh through Git Bash
# ============================================================

try {

    $Process = Start-Process `
        -FilePath $GitBash `
        -ArgumentList "--login", "-c", "bash `"$GitBashScriptPath`"" `
        -Wait `
        -PassThru `
        -NoNewWindow

}
catch {

    Fail-Installation "Unable to execute Security Compliance installer. $($_.Exception.Message)"
}

# ============================================================
# Check Result
# ============================================================

if ($Process.ExitCode -ne 0) {

    Write-Host ""
    Write-ErrorMessage "Security Compliance installer returned an error."
    Write-ErrorMessage "Exit code: $($Process.ExitCode)"
    Write-Host ""

    exit $Process.ExitCode
}

# ============================================================
# Final Success
# ============================================================

Write-Host ""
Write-Host "============================================================"
Write-Host "       SECURITY COMPLIANCE INSTALLATION COMPLETE"
Write-Host "============================================================"
Write-Host ""

Write-Success "Git for Windows / Git Bash is available."
Write-Success "Security Compliance installer executed successfully."
Write-Success "Gitleaks $GITLEAKS_VERSION installation completed."
Write-Success "Global Git security scanning has been configured."

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
        Remove-Item $GitInstaller -Force -ErrorAction SilentlyContinue
    }

}
catch {
    # Cleanup failure should not make successful installation fail.
}

exit 0
