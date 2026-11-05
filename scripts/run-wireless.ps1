[CmdletBinding()]
param(
    [string]$Serial = "",
    [string]$Adb = "",
    [string]$NdkRoot = "",
    [ValidateSet("Interactive", "Full", "ModuleOnly", "Stage", "Status")]
    [string]$Mode = "Interactive",
    [switch]$NoLaunch,
    [switch]$NonInteractive
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $repoRoot

$targetKernel = "5.10.252-android12-9-ga431fb50f9a2"
$targetBuild = "8.0.0.191"
$cacheDir = Join-Path $repoRoot ".cache"
$lastTargetFile = Join-Path $cacheDir "wireless-target.txt"
$runScript = Join-Path $repoRoot "scripts\run-ksu.ps1"
$fetchScript = Join-Path $repoRoot "scripts\fetch-bundle.ps1"
$buildScript = Join-Path $repoRoot "scripts\build.ps1"

function Find-UpPath {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [int]$Depth = 4
    )
    $cursor = $repoRoot
    for ($i = 0; $i -le $Depth; $i++) {
        $candidate = Join-Path $cursor $RelativePath
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
        $parent = Split-Path -Parent $cursor
        if (-not $parent -or $parent -eq $cursor) { break }
        $cursor = $parent
    }
    return $null
}

function Resolve-Adb {
    $candidates = @()
    if ($Adb) { $candidates += $Adb }
    if ($env:ADB) { $candidates += $env:ADB }

    $localAdb = Find-UpPath "tools\platform-tools\adb.exe"
    if ($localAdb) { $candidates += $localAdb }

    $sdkAdb = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
    if (Test-Path -LiteralPath $sdkAdb) { $candidates += $sdkAdb }

    $command = Get-Command adb -ErrorAction SilentlyContinue
    if ($command) { $candidates += $command.Source }

    foreach ($candidate in $candidates) {
        if (-not $candidate) { continue }
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
        $found = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($found) { return $found.Source }
    }
    throw "adb not found. Pass -Adb, set ADB, or install Android platform-tools."
}

function Resolve-Ndk {
    $candidates = @()
    if ($NdkRoot) { $candidates += $NdkRoot }
    foreach ($name in @("ANDROID_NDK_HOME", "ANDROID_NDK_ROOT", "NDK_ROOT")) {
        $value = [Environment]::GetEnvironmentVariable($name)
        if ($value) { $candidates += $value }
    }
    $localNdk = Find-UpPath "tools\android-sdk\ndk\android-ndk-r28c"
    if ($localNdk) { $candidates += $localNdk }
    $repoNdk = Join-Path $repoRoot "ndk\android-ndk-r28c"
    if (Test-Path -LiteralPath $repoNdk) { $candidates += $repoNdk }

    foreach ($candidate in $candidates) {
        if (-not $candidate) { continue }
        if (Test-Path -LiteralPath (Join-Path $candidate "toolchains\llvm\prebuilt")) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

function Get-AdbDevices {
    $lines = & $script:AdbPath devices 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "adb devices failed: $($lines -join ' ')"
    }
    foreach ($line in $lines) {
        if ($line -match "^\s*(\S+)\s+device\s*$") {
            $Matches[1]
        }
    }
}

function Connect-MdnsTargets {
    & $script:AdbPath mdns check 2>&1 | Out-Null
    $lines = & $script:AdbPath mdns services 2>&1
    if ($LASTEXITCODE -ne 0) { return }

    $addresses = @()
    foreach ($line in $lines) {
        if ($line -match "(_adb-tls-connect\._tcp|_adb\._tcp)" -and
            $line -match "((?:\d{1,3}\.){3}\d{1,3}:\d+)") {
            $addresses += $Matches[1]
        }
    }
    $addresses = @($addresses | Select-Object -Unique)
    foreach ($address in $addresses) {
        Write-Host "== trying wireless target $address"
        & $script:AdbPath connect $address 2>&1 | ForEach-Object { Write-Host "   $_" }
    }
}

function Select-AdbDevice {
    if ($Serial) {
        if ($Serial -match ":\d+$") {
            Write-Host "== connecting to $Serial"
            & $script:AdbPath connect $Serial 2>&1 | ForEach-Object { Write-Host "   $_" }
        }
        $devices = @(Get-AdbDevices)
        if ($devices -contains $Serial) { return $Serial }
        throw "specified ADB device is not connected: $Serial"
    }

    if (Test-Path -LiteralPath $lastTargetFile) {
        $lastTarget = (Get-Content -LiteralPath $lastTargetFile -Raw).Trim()
        if ($lastTarget) {
            Write-Host "== trying last wireless target $lastTarget"
            & $script:AdbPath connect $lastTarget 2>&1 | ForEach-Object { Write-Host "   $_" }
        }
    }

    $devices = @(Get-AdbDevices)
    if ($devices.Count -eq 0) {
        Write-Host "== searching for wireless debugging via mDNS"
        Connect-MdnsTargets
        $devices = @(Get-AdbDevices)
    }

    if ($devices.Count -eq 0) {
        if ($NonInteractive) {
            throw "no ADB device found; open wireless debugging on the pad and try again"
        }
        Write-Host ""
        Write-Host "No ADB device found."
        Write-Host "On the pad: Settings > Developer options > Wireless debugging."
        $manual = Read-Host "Enter IP:PORT (or press Enter to quit)"
        if ([string]::IsNullOrWhiteSpace($manual)) { exit 1 }
        & $script:AdbPath connect $manual 2>&1 | ForEach-Object { Write-Host "   $_" }
        Start-Sleep -Seconds 1
        $devices = @(Get-AdbDevices)
    }

    if ($devices.Count -eq 0) {
        throw "ADB connection failed. Re-open wireless debugging and check the pairing."
    }
    if ($devices.Count -eq 1) { return $devices[0] }

    Write-Host ""
    Write-Host "Multiple ADB devices:"
    for ($i = 0; $i -lt $devices.Count; $i++) {
        Write-Host ("  [{0}] {1}" -f ($i + 1), $devices[$i])
    }
    if ($NonInteractive) {
        throw "multiple ADB devices; pass -Serial"
    }
    $choice = Read-Host "Select device number"
    $index = 0
    if (-not [int]::TryParse($choice, [ref]$index) -or
        $index -lt 1 -or $index -gt $devices.Count) {
        throw "invalid device selection"
    }
    return $devices[$index - 1]
}

function Get-DeviceFacts {
    $kernel = (& $script:AdbPath -s $script:Serial shell uname -r 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "failed to read kernel version from $script:Serial"
    }
    $fingerprint = (& $script:AdbPath -s $script:Serial shell getprop ro.build.fingerprint 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "failed to read build fingerprint from $script:Serial"
    }
    if ($kernel -ne $targetKernel) {
        throw "kernel mismatch: got '$kernel', expected '$targetKernel'"
    }
    if ($fingerprint -notmatch [regex]::Escape($targetBuild)) {
        throw "build mismatch: expected $targetBuild in ro.build.fingerprint, got '$fingerprint'"
    }
    [pscustomobject]@{
        Kernel = $kernel
        Fingerprint = $fingerprint
    }
}

function Show-Status {
    param([Parameter(Mandatory = $true)]$Facts)

    Write-Host "== device: $script:Serial"
    Write-Host "== kernel: $($Facts.Kernel)"
    Write-Host "== build:  $($Facts.Fingerprint)"

    $modules = (& $script:AdbPath -s $script:Serial shell "grep -i kernelsu /proc/modules 2>/dev/null || true" 2>&1 | Out-String).Trim()
    if ($modules) {
        Write-Host "== kernelsu: loaded"
        Write-Host "   $modules"
    } else {
        Write-Host "== kernelsu: not loaded"
    }

    $enforce = (& $script:AdbPath -s $script:Serial shell getenforce 2>&1 | Out-String).Trim()
    if ($enforce) { Write-Host "== selinux: $enforce" }

    $manager = (& $script:AdbPath -s $script:Serial shell "pm list packages me.weishu.kernelsu 2>/dev/null || true" 2>&1 | Out-String).Trim()
    if ($manager -match "me\.weishu\.kernelsu") {
        Write-Host "== manager: installed"
    } else {
        Write-Host "== manager: not installed"
    }
}

function Ensure-Bundle {
    $required = @(
        "kernelsu.ko",
        "ksud",
        "magiskpolicy",
        "KernelSU_v3.3.0_32601-release.apk"
    )
    $missing = @()
    foreach ($name in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $repoRoot "bundle\$name"))) {
            $missing += $name
        }
    }
    if ($missing.Count -gt 0) {
        Write-Host "== runtime bundle missing: $($missing -join ', ')"
        Write-Host "== fetching pinned files"
        & $fetchScript
    }
}

function Ensure-Build {
    $exploit = Join-Path $repoRoot "exploit\build\honor-HEY2-W09_8.0.0.191\bin\exploit_static"
    $loadKo = Join-Path $repoRoot "ksu\load_ko"
    $kmsgDumper = Join-Path $repoRoot "ksu\kmsg_dumper"
    $missing = @($exploit, $loadKo, $kmsgDumper) | Where-Object {
        -not (Test-Path -LiteralPath $_)
    }
    if (-not $missing) { return }

    $ndk = Resolve-Ndk
    if (-not $ndk) {
        throw "NDK not found. Pass -NdkRoot or set ANDROID_NDK_HOME."
    }
    Write-Host "== local binaries missing; building with $ndk"
    & $buildScript -NdkRoot $ndk
}

function Show-Menu {
    Write-Host ""
    Write-Host "  1) Status only"
    Write-Host "  2) Stage only (no exploit)"
    Write-Host "  3) Module-only late-load (authorized)"
    Write-Host "  4) Full verified flow (authorized)"
    Write-Host "  Q) Quit"
    $choice = Read-Host "Select [1-4/Q] (default 4)"
    if ([string]::IsNullOrWhiteSpace($choice)) { return "Full" }
    switch ($choice.Trim().ToUpperInvariant()) {
        "1" { return "Status" }
        "2" { return "Stage" }
        "3" { return "ModuleOnly" }
        "4" { return "Full" }
        "Q" { return "Quit" }
        default { throw "invalid menu selection" }
    }
}

function Confirm-Launch {
    Write-Host ""
    Write-Host "WARNING: this will launch the GhostLock exploit."
    Write-Host "Target: HONOR Pad 9 HEY2-W09 / MagicOS $targetBuild / Linux $targetKernel"
    Write-Host "Reboot is the cleanup boundary. Do not use this on another device."
    if ($NonInteractive) {
        throw "authorization confirmation required; use -NoLaunch or run interactively"
    }
    $answer = Read-Host "Type RUN to launch, or press Enter to cancel"
    if ($answer -cne "RUN") {
        Write-Host "Cancelled."
        exit 0
    }
}

try {
    $script:AdbPath = Resolve-Adb
    Write-Host "== adb: $script:AdbPath"

    $script:Serial = Select-AdbDevice
    Write-Host "== connected: $script:Serial"

    $facts = Get-DeviceFacts
    Show-Status -Facts $facts

    if ($Mode -eq "Interactive") {
        $Mode = Show-Menu
    }
    if ($Mode -eq "Quit") { exit 0 }

    if ($Mode -eq "Status") {
        exit 0
    }

    if ($Mode -eq "Stage" -or $NoLaunch) {
        $Mode = "Stage"
    } elseif ($Mode -eq "Full" -or $Mode -eq "ModuleOnly") {
        Confirm-Launch
    }

    Ensure-Bundle
    Ensure-Build

    if ($Mode -eq "Full") {
        $stages = 1
        $allowShell = 1
        $installManager = $true
    } else {
        $stages = 0
        $allowShell = 0
        $installManager = $false
    }

    $runArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $runScript,
        "-Serial", $script:Serial,
        "-Adb", $script:AdbPath,
        "-Stages", "$stages",
        "-Enforce", "0",
        "-AllowShell", "$allowShell"
    )
    if ($installManager) { $runArgs += "-InstallManager" }
    if ($Mode -eq "Stage") {
        $runArgs += "-NoLaunch"
    } else {
        $runArgs += "-Authorize"
    }

    New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
    [IO.File]::WriteAllText($lastTargetFile, $script:Serial, [Text.UTF8Encoding]::new($false))

    $hostExe = if ($PSVersionTable.PSEdition -eq "Core") {
        Join-Path $PSHOME "pwsh.exe"
    } else {
        Join-Path $PSHOME "powershell.exe"
    }
    & $hostExe @runArgs
    exit $LASTEXITCODE
} catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host "If this is a connection error, open Wireless debugging on the pad and try again."
    exit 1
}
