[CmdletBinding()]
param(
    [string]$Serial = "",
    [string]$Adb = "",
    [int]$Stages = 0,
    [int]$Enforce = 0,
    [int]$AllowShell = 0,
    [switch]$InstallManager,
    [switch]$Authorize,
    [switch]$NoLaunch,
    [switch]$OpenManager
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$bundle = Join-Path $repoRoot "bundle"
$targetKernel = "5.10.252-android12-9-ga431fb50f9a2"
$targetBuild = "8.0.0.191"
$exploit = Join-Path $repoRoot "exploit\build\honor-HEY2-W09_8.0.0.191\bin\exploit_static"

if ($Stages -notin 0, 1) { throw "Stages must be 0 or 1" }
if ($Enforce -notin 0, 1) { throw "Enforce must be 0 or 1" }
if ($AllowShell -notin 0, 1) { throw "AllowShell must be 0 or 1" }

function Resolve-Adb {
    param([string]$Requested)
    $candidates = @()
    if ($Requested) { $candidates += $Requested }
    if ($env:ADB) { $candidates += $env:ADB }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return (Resolve-Path -LiteralPath $candidate).Path }
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
    }
    $command = Get-Command adb -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    throw "adb not found. Pass -Adb or set ADB."
}

$script:Adb = Resolve-Adb -Requested $Adb
$script:Serial = $Serial

function Invoke-Adb {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$AdbArgs)
    $out = & $script:Adb -s $script:Serial @AdbArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "adb failed ($LASTEXITCODE): $out"
    }
    return $out
}

function Invoke-AdbOptional {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$AdbArgs)
    $out = & $script:Adb -s $script:Serial @AdbArgs 2>&1
    return @{
        Ok = ($LASTEXITCODE -eq 0)
        Output = ($out | Out-String).Trim()
    }
}

function Get-DeviceSerial {
    $lines = & $script:Adb devices 2>&1
    foreach ($line in $lines) {
        if ($line -match "^\s*(\S+)\s+device\s*$") { return $Matches[1] }
    }
    throw "no adb device; open wireless debugging and confirm adb devices"
}

if (-not $script:Serial) { $script:Serial = Get-DeviceSerial }
Write-Host "== device: $script:Serial"

$kernel = (Invoke-Adb shell "uname -r").Trim()
if ($kernel -ne $targetKernel) {
    throw "kernel mismatch: got '$kernel', expected '$targetKernel'"
}
$fingerprint = (Invoke-Adb shell "getprop ro.build.fingerprint").Trim()
if ($fingerprint -notmatch [regex]::Escape($targetBuild)) {
    throw "build mismatch: expected $targetBuild in ro.build.fingerprint, got '$fingerprint'"
}
Write-Host "== kernel: $kernel"
Write-Host "== build: $fingerprint"

$required = @(
    "kernelsu.ko",
    "ksud",
    "magiskpolicy",
    "KernelSU_v3.3.0_32601-release.apk"
)
foreach ($name in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $bundle $name))) {
        throw "missing bundle/$name; run scripts/fetch-bundle.ps1"
    }
}
if (-not (Test-Path -LiteralPath $exploit)) {
    throw "missing exploit_static; run scripts/build.ps1"
}

if ($InstallManager) {
    Write-Host "== installing KernelSU Manager v3.3.0"
    $apk = Join-Path $bundle "KernelSU_v3.3.0_32601-release.apk"
    $installOutput = & $script:Adb -s $script:Serial install -r -g $apk 2>&1
    if ($LASTEXITCODE -ne 0) { throw "adb install failed: $installOutput" }
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$rd = "/data/local/tmp/ksu_run_$stamp"
Write-Host "== rundir: $rd"
Invoke-Adb shell "mkdir -p $rd" | Out-Null

$files = @(
    @{ Local = (Join-Path $bundle "kernelsu.ko"); Remote = "kernelsu.ko" },
    @{ Local = (Join-Path $repoRoot "ksu\load_ko"); Remote = "load_ko" },
    @{ Local = (Join-Path $bundle "ksud"); Remote = "ksud" },
    @{ Local = (Join-Path $bundle "magiskpolicy"); Remote = "magiskpolicy" },
    @{ Local = (Join-Path $repoRoot "ksu\kmsg_dumper"); Remote = "kmsg_dumper" },
    @{ Local = (Join-Path $repoRoot "ksu\ksu_rules"); Remote = "ksu_rules" },
    @{ Local = $exploit; Remote = "exploit" }
)
foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath $file.Local)) { throw "missing local file: $($file.Local)" }
    & $script:Adb -s $script:Serial push $file.Local "$rd/$($file.Remote)" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "push failed: $($file.Local)" }
}
Invoke-Adb shell "chmod 755 $rd/exploit $rd/load_ko $rd/magiskpolicy $rd/ksud $rd/kmsg_dumper" | Out-Null

$template = Get-Content -LiteralPath (Join-Path $repoRoot "ksu\ksu_loader.tmpl") -Raw
$loader = $template
$loader = $loader.Replace("@RUNDIR@", $rd)
$loader = $loader.Replace("@STAMP@", $stamp)
$loader = $loader.Replace("@FREEZE_HISECD@", "1")
$loader = $loader.Replace("@ALLOW_SHELL@", "$AllowShell")
$loader = $loader.Replace("@STAGES@", "$Stages")
$loader = $loader.Replace("@ENFORCE@", "$Enforce")
$loader = $loader.Replace("`r`n", "`n").Replace("`r", "`n")
$loaderPath = Join-Path $bundle "ksu_loader.generated.sh"
[IO.File]::WriteAllText($loaderPath, $loader, [Text.UTF8Encoding]::new($false))
& $script:Adb -s $script:Serial push $loaderPath "$rd/ksu_loader.sh" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "push failed: ksu_loader.sh" }
Invoke-Adb shell "chmod 755 $rd/ksu_loader.sh" | Out-Null

Write-Host "== staged: Stages=$Stages Enforce=$Enforce AllowShell=$AllowShell"
if ($NoLaunch -or -not $Authorize) {
    Write-Host "== NOT launching (authorization gate)."
    Write-Host "== To run: .\scripts\run-ksu.ps1 -Serial '$script:Serial' -Stages $Stages -Enforce $Enforce -AllowShell $AllowShell -Authorize"
    exit 0
}

Write-Host "== launching GhostLock + KernelSU late-load"
Invoke-Adb shell "nohup env KSU_RUNDIR=$rd $rd/exploit > $rd/gl.log 2>&1 &" | Out-Null

$deadline = (Get-Date).AddMinutes(6)
$rebooted = $false
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    $state = (& $script:Adb -s $script:Serial get-state 2>&1 | Out-String).Trim()
    if ($state -ne "device") {
        Write-Host "== adb lost; waiting for reboot/reconnect"
        $rebooted = $true
        $returned = $false
        for ($i = 0; $i -lt 24; $i++) {
            Start-Sleep -Seconds 5
            $state = (& $script:Adb -s $script:Serial get-state 2>&1 | Out-String).Trim()
            if ($state -eq "device") { $returned = $true; break }
        }
        if (-not $returned) {
            Write-Host "== adb did not return. Re-open wireless debugging, then reconnect."
            exit 2
        }
        break
    }

    $mods = (Invoke-Adb shell "grep -qi kernelsu /proc/modules && echo YES || echo NO").Trim()
    if ($mods -eq "YES") {
        Write-Host "== KernelSU module loaded"
        $loadLog = Invoke-AdbOptional shell "tail -n 60 $rd/ksu_load.log 2>/dev/null"
        if ($loadLog.Ok -and $loadLog.Output) {
            Write-Host "== load log:"
            Write-Host $loadLog.Output
        }
        $loadKoLog = Invoke-AdbOptional shell "cat $rd/loadko_result.log 2>/dev/null"
        if ($loadKoLog.Ok -and $loadKoLog.Output) {
            Write-Host "== load_ko result:"
            Write-Host $loadKoLog.Output
        }
        $enforce = Invoke-AdbOptional shell "getenforce"
        if ($enforce.Ok) { Write-Host "== selinux: $($enforce.Output)" }
        Write-Host "== modules:"
        Invoke-Adb shell "grep -i kernelsu /proc/modules"

        if ($Stages -eq 1 -and $AllowShell -eq 1) {
            $su = Invoke-AdbOptional shell "su -c id"
            if ($su.Ok) { Write-Host "== su: $($su.Output)" }
        }
        if ($OpenManager) {
            Invoke-AdbOptional shell "am start -n me.weishu.kernelsu/.ui.MainActivity" | Out-Null
        }
        exit 0
    }
}

if ($rebooted) {
    Write-Host "== attempt missed (device rebooted). Re-open wireless debugging and re-run."
    exit 2
}

Write-Host "== timeout; last exploit log:"
$tail = Invoke-AdbOptional shell "tail -n 80 $rd/gl.log 2>/dev/null"
if ($tail.Ok -and $tail.Output) { Write-Host $tail.Output }
exit 1
