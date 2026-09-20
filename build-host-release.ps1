param(
    [Parameter(Mandatory = $false)]
    [string]$InnoScript = ".\installer\CounterIQ-Host.iss"
)

$ErrorActionPreference = "Stop"

# ============================================================
# Helpers
# ============================================================

function Prompt-ExistingFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description,

        [Parameter(Mandatory = $false)]
        [string]$SuggestedPath
    )

    $candidate = $SuggestedPath

    while ($true) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $candidate = $candidate.Trim('"')

            if (Test-Path $candidate -PathType Leaf) {
                return (Resolve-Path $candidate).Path
            }
        }

        Write-Host ""
        Write-Host "$Description was not found."

        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            Write-Host "Tried:"
            Write-Host "  $candidate"
        }

        Write-Host ""
        $candidate = Read-Host "Enter the full path for $Description"

        if ([string]::IsNullOrWhiteSpace($candidate)) {
            Write-Host "Path cannot be blank. Please try again."
            $candidate = $null
        }
    }
}


function Prompt-ExistingDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description,

        [Parameter(Mandatory = $false)]
        [string]$SuggestedPath
    )

    $candidate = $SuggestedPath

    while ($true) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $candidate = $candidate.Trim('"')

            if (Test-Path $candidate -PathType Container) {
                return (Resolve-Path $candidate).Path
            }
        }

        Write-Host ""
        Write-Host "$Description was not found."

        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            Write-Host "Tried:"
            Write-Host "  $candidate"
        }

        Write-Host ""
        $candidate = Read-Host "Enter the full path for $Description"

        if ([string]::IsNullOrWhiteSpace($candidate)) {
            Write-Host "Path cannot be blank. Please try again."
            $candidate = $null
        }
    }
}


function Ask-YesNoDefaultYes {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Question
    )

    while ($true) {
        $answer = Read-Host "$Question [Y/n]"

        if ([string]::IsNullOrWhiteSpace($answer)) {
            return $true
        }

        switch ($answer.Trim().ToLowerInvariant()) {
            "y"   { return $true }
            "yes" { return $true }
            "n"   { return $false }
            "no"  { return $false }
            default {
                Write-Host "Please enter Y or N."
            }
        }
    }
}


function Find-InnoCompiler {
    param(
        [string]$SavedPathFile
    )

    # 1. Previously saved user-selected path
    if (Test-Path $SavedPathFile -PathType Leaf) {
        $saved = (Get-Content $SavedPathFile -Raw).Trim().Trim('"')

        if (-not [string]::IsNullOrWhiteSpace($saved) -and
            (Test-Path $saved -PathType Leaf)) {
            return (Resolve-Path $saved).Path
        }
    }

    # 2. Common locations
    $candidates = @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles}\Inno Setup 6\ISCC.exe",
        "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
        "C:\Program Files\Inno Setup 6\ISCC.exe"
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate -PathType Leaf) {
            return (Resolve-Path $candidate).Path
        }
    }

    return $null
}


# ============================================================
# Known CounterIQ paths
# ============================================================

$FrontendRootDefault = "E:\learning\flutter\enterprise_pos"
$BackendRootDefault  = "E:\learning\go\pos-backend"

$FrontendRoot = Prompt-ExistingDirectory `
    -Description "CounterIQ frontend project folder" `
    -SuggestedPath $FrontendRootDefault

$BackendRoot = Prompt-ExistingDirectory `
    -Description "CounterIQ backend project folder" `
    -SuggestedPath $BackendRootDefault

$VersionFile = Join-Path $FrontendRoot "version.txt"
$VersionFile = Prompt-ExistingFile `
    -Description "CounterIQ version.txt file" `
    -SuggestedPath $VersionFile

$Version = (Get-Content $VersionFile -Raw).Trim()

if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "Invalid CounterIQ version '$Version'. Expected format like 1.0.11"
}

$ManifestUrl = "https://raw.githubusercontent.com/moeezs82/counteriq-updates/main/host/latest.json"

$ReleaseDir       = Join-Path $FrontendRoot "build\windows\x64\runner\Release"
$FrontendExe      = Join-Path $ReleaseDir "CounterIQ.exe"
$BackendTargetDir = Join-Path $ReleaseDir "backend"
$BackendTarget    = Join-Path $BackendTargetDir "counteriq-backend.exe"

# Resolve Inno script. If default isn't found, prompt instead of failing.
if ([System.IO.Path]::IsPathRooted($InnoScript)) {
    $InnoScriptCandidate = $InnoScript
}
else {
    $InnoScriptCandidate = Join-Path $FrontendRoot $InnoScript
}

$InnoScriptFullPath = Prompt-ExistingFile `
    -Description "CounterIQ Inno Setup script (.iss)" `
    -SuggestedPath $InnoScriptCandidate

$SavedIsccPathFile = Join-Path $FrontendRoot ".counteriq-iscc-path.txt"


Write-Host ""
Write-Host "============================================================"
Write-Host " CounterIQ Host Release Build"
Write-Host " Version : $Version"
Write-Host "============================================================"
Write-Host ""


# ============================================================
# Reuse successful build if it already exists
# ============================================================

$ReuseExisting = $false

if ((Test-Path $FrontendExe -PathType Leaf) -and
    (Test-Path $BackendTarget -PathType Leaf)) {

    Write-Host "Existing complete Host build found:"
    Write-Host " Frontend : $FrontendExe"
    Write-Host " Backend  : $BackendTarget"
    Write-Host ""

    $ReuseExisting = Ask-YesNoDefaultYes `
        "Reuse this existing frontend/backend build and continue directly to Inno packaging?"
}


if (-not $ReuseExisting) {

    # ========================================================
    # 1. Flutter build
    # ========================================================

    Set-Location $FrontendRoot

    Write-Host "[1/6] Cleaning Flutter project..."
    flutter clean

    if ($LASTEXITCODE -ne 0) {
        throw "flutter clean failed."
    }

    Write-Host "[2/6] Restoring Flutter packages..."
    flutter pub get

    if ($LASTEXITCODE -ne 0) {
        throw "flutter pub get failed."
    }

    Write-Host "[3/6] Building CounterIQ Host frontend..."

    flutter build windows --release `
        --dart-define=COUNTERIQ_BACKEND_MODE=local `
        --dart-define=COUNTERIQ_LOCAL_ROLE=host `
        --dart-define=COUNTERIQ_LOCAL_HOST_LAN=true `
        --dart-define=COUNTERIQ_APP_VERSION=$Version `
        --dart-define=COUNTERIQ_UPDATE_MANIFEST_URL=$ManifestUrl `
        --dart-define=COUNTERIQ_UPDATE_CHANNEL=stable

    if ($LASTEXITCODE -ne 0) {
        throw "Flutter Windows Host build failed."
    }

    # ========================================================
    # 2. Go backend build
    # ========================================================

    Write-Host "[4/6] Building CounterIQ Go backend..."

    New-Item -ItemType Directory -Force -Path $BackendTargetDir | Out-Null

    Set-Location $BackendRoot

    go build `
        -ldflags="-H windowsgui" `
        -o $BackendTarget `
        ./cmd/api

    if ($LASTEXITCODE -ne 0) {
        throw "CounterIQ backend build failed."
    }

    if (-not (Test-Path $FrontendExe -PathType Leaf)) {
        throw "CounterIQ.exe was not found after Flutter build: $FrontendExe"
    }

    if (-not (Test-Path $BackendTarget -PathType Leaf)) {
        throw "counteriq-backend.exe was not found after backend build: $BackendTarget"
    }
}
else {
    Write-Host "Skipping Flutter and Go rebuild."
}


# ============================================================
# Verify package
# ============================================================

Write-Host ""
Write-Host "Host package verification:"
Write-Host " Frontend : $FrontendExe"
Write-Host " Backend  : $BackendTarget"
Write-Host ""


# ============================================================
# Find or prompt for Inno compiler
# ============================================================

$Iscc = Find-InnoCompiler -SavedPathFile $SavedIsccPathFile

while ([string]::IsNullOrWhiteSpace($Iscc) -or
       -not (Test-Path $Iscc -PathType Leaf)) {

    Write-Host ""
    Write-Host "Inno Setup compiler (ISCC.exe) was not found automatically."
    Write-Host ""
    Write-Host "Example:"
    Write-Host "  C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
    Write-Host ""

    $enteredPath = Read-Host "Enter the full path to ISCC.exe"

    if ([string]::IsNullOrWhiteSpace($enteredPath)) {
        Write-Host "Path cannot be blank. Please try again."
        continue
    }

    $enteredPath = $enteredPath.Trim('"')

    if (-not (Test-Path $enteredPath -PathType Leaf)) {
        Write-Host "That file does not exist. Please try again."
        continue
    }

    $Iscc = (Resolve-Path $enteredPath).Path

    # Remember it so future releases never ask again.
    Set-Content `
        -Path $SavedIsccPathFile `
        -Value $Iscc `
        -Encoding UTF8
}

Write-Host ""
Write-Host "Using Inno compiler:"
Write-Host " $Iscc"
Write-Host ""


# ============================================================
# 5. Compile Inno installer
# ============================================================

Write-Host "[5/6] Building CounterIQ Host installer..."

Set-Location $FrontendRoot

& $Iscc "/DMyAppVersion=$Version" $InnoScriptFullPath

if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup compilation failed."
}


# ============================================================
# 6. Resolve installer and SHA
# ============================================================

$InstallerDir  = Join-Path (Split-Path -Parent $InnoScriptFullPath) "output"
$InstallerPath = Join-Path $InstallerDir "CounterIQ-Host-Setup-$Version.exe"

while (-not (Test-Path $InstallerPath -PathType Leaf)) {

    Write-Host ""
    Write-Host "Expected installer was not found:"
    Write-Host "  $InstallerPath"
    Write-Host ""
    Write-Host "If your Inno OutputDir is different, enter the actual installer path."

    $enteredInstaller = Read-Host "Full path to CounterIQ Host installer"

    if ([string]::IsNullOrWhiteSpace($enteredInstaller)) {
        Write-Host "Path cannot be blank. Please try again."
        continue
    }

    $enteredInstaller = $enteredInstaller.Trim('"')

    if (-not (Test-Path $enteredInstaller -PathType Leaf)) {
        Write-Host "That installer file does not exist. Please try again."
        continue
    }

    $InstallerPath = (Resolve-Path $enteredInstaller).Path
}

Write-Host "[6/6] Calculating SHA-256..."

$Hash = (Get-FileHash $InstallerPath -Algorithm SHA256).Hash


# ============================================================
# Final
# ============================================================

Write-Host ""
Write-Host "============================================================"
Write-Host " CounterIQ Host Release Completed"
Write-Host "============================================================"
Write-Host "Version   : $Version"
Write-Host "Frontend  : $FrontendExe"
Write-Host "Backend   : $BackendTarget"
Write-Host "Installer : $InstallerPath"
Write-Host "SHA-256   : $Hash"
Write-Host "============================================================"
Write-Host ""