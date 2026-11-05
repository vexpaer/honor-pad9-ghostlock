[CmdletBinding()]
param(
    [string]$NdkRoot = "",
    [string]$Api = "35",
    [switch]$Clean
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$exploitDir = Join-Path $repoRoot "exploit"
$ksuDir = Join-Path $repoRoot "ksu"
$buildDir = Join-Path $exploitDir "build"
$buildTemp = Join-Path $repoRoot ".cache\build-tmp"
$project = "honor-HEY2-W09_8.0.0.191"
New-Item -ItemType Directory -Force -Path $buildTemp | Out-Null
# Keep compiler temporary objects off the system drive when the repository is
# on a different volume.
$env:TMP = $buildTemp
$env:TEMP = $buildTemp
$env:TMPDIR = $buildTemp

if (-not $NdkRoot) {
    $candidates = @(
        $env:ANDROID_NDK_HOME,
        $env:ANDROID_NDK_ROOT,
        $env:NDK_ROOT
    ) | Where-Object { $_ }
    $NdkRoot = $candidates | Select-Object -First 1
}
if (-not $NdkRoot) {
    throw "NDK not found. Pass -NdkRoot or set ANDROID_NDK_HOME."
}
$NdkRoot = [IO.Path]::GetFullPath($NdkRoot)
if (-not (Test-Path -LiteralPath $NdkRoot)) { throw "NDK path does not exist: $NdkRoot" }

$onWindows = [bool]$IsWindows
if (-not $onWindows -and $env:OS -eq "Windows_NT") { $onWindows = $true }
$hostTag = if ($onWindows) { "windows-x86_64" } elseif ($IsMacOS) { "darwin-x86_64" } else { "linux-x86_64" }
$toolchain = Join-Path $NdkRoot "toolchains\llvm\prebuilt\$hostTag"
if (-not (Test-Path -LiteralPath $toolchain)) {
    $prebuilt = Join-Path $NdkRoot "toolchains\llvm\prebuilt"
    $toolchain = Get-ChildItem -LiteralPath $prebuilt -Directory -ErrorAction Stop |
        Where-Object { Test-Path (Join-Path $_.FullName "bin") } |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $toolchain) { throw "could not locate the NDK LLVM toolchain under $NdkRoot" }

$ccName = "aarch64-linux-android$Api-clang"
$cc = Join-Path $toolchain "bin\$ccName"
if ($onWindows) {
    # The NDK's .cmd wrapper does not reliably propagate LASTEXITCODE through
    # a PowerShell function; call clang.exe directly and pass --target below.
    $clangExe = Join-Path $toolchain "bin\clang.exe"
    if (Test-Path -LiteralPath $clangExe) { $cc = $clangExe }
    elseif (Test-Path -LiteralPath "$cc.cmd") { $cc = "$cc.cmd" }
}
if (-not (Test-Path -LiteralPath $cc)) { throw "NDK compiler not found: $cc" }

$sysroot = Join-Path $toolchain "sysroot"
$resourceRoot = Join-Path $toolchain "lib\clang"
$resource = Get-ChildItem -LiteralPath $resourceRoot -Directory |
    Sort-Object Name |
    Select-Object -Last 1
if (-not $resource) { throw "NDK clang resource directory not found under $resourceRoot" }

if ($Clean) {
    if (Test-Path -LiteralPath $buildDir) { Remove-Item -LiteralPath $buildDir -Recurse -Force }
    foreach ($tool in @("load_ko", "kmsg_dumper")) {
        $p = Join-Path $ksuDir $tool
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
    }
}

$outDir = Join-Path $buildDir "$project\bin"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$target = "--target=aarch64-linux-android$Api"
$common = @(
    $target,
    "--sysroot=$sysroot",
    "-resource-dir", $resource.FullName,
    "--rtlib=compiler-rt",
    "--unwindlib=none",
    "-O2",
    "-g0",
    "-Wall",
    "-Wextra",
    "-Isrc",
    ('-DTARGET_CONFIG_H=<targets/{0}/target.h>' -f $project)
)
$linkCommon = @(
    "-fuse-ld=lld",
    "-Wl,-rpath-link,$(Join-Path $sysroot "usr\lib\aarch64-linux-android\$Api")",
    "-L$(Join-Path $sysroot "usr\lib\aarch64-linux-android\$Api")",
    "-L$(Join-Path $sysroot "usr\lib\aarch64-linux-android")"
)
$sources = @(
    "src\launcher.c",
    "src\main.c",
    "src\util.c",
    "src\slide.c",
    "src\sysctl.c"
)

function Invoke-Clang {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    & $cc @Arguments
    if ($LASTEXITCODE -ne 0) { throw "clang failed with exit code $LASTEXITCODE" }
}

Push-Location $exploitDir
try {
    $dynamic = Join-Path $outDir "exploit"
    $static = Join-Path $outDir "exploit_static"
    $pie = @("-fPIE", "-pie") + $common + $sources + $linkCommon +
        @("-Wl,-dynamic-linker,/system/bin/linker64", "-o", $dynamic, "-pthread")
    $staticArgs = @("-static") + $common + $sources + $linkCommon +
        @("-o", $static, "-pthread")
    Invoke-Clang -Arguments $pie
    Invoke-Clang -Arguments $staticArgs
} finally {
    Pop-Location
}

$toolArgs = @(
    $target,
    "--sysroot=$sysroot",
    "-resource-dir", $resource.FullName,
    "--rtlib=compiler-rt",
    "--unwindlib=none",
    "-static",
    "-O2",
    "-Wall",
    "-Wextra",
    "-Isrc"
)
$loadKo = Join-Path $ksuDir "load_ko"
$kmsgDumper = Join-Path $ksuDir "kmsg_dumper"
Invoke-Clang -Arguments ($toolArgs + @(
    (Join-Path $ksuDir "load_ko.c"),
    "-o", $loadKo
))
Invoke-Clang -Arguments ($toolArgs + @(
    (Join-Path $ksuDir "kmsg_dumper.c"),
    "-o", $kmsgDumper
))

Write-Host "== built:"
foreach ($p in @($dynamic, $static, $loadKo, $kmsgDumper)) {
    $hash = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
    Write-Host ("   {0}  {1}" -f $hash, $p)
}
