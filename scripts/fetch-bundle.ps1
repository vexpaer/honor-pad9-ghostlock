[CmdletBinding()]
param(
    [string]$Destination = "",
    [string]$Cache = "",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $Destination) { $Destination = Join-Path $repoRoot "bundle" }
if (-not $Cache) { $Cache = Join-Path $repoRoot ".cache" }

$ghostlockUrl = "https://github.com/yakidango-official/GhostLock-H80GT/releases/download/v0.3.1/ghostlock.tar.gz"
$ghostlockSha = "A5A3CFF2C3172BD5DEBE2A4E4F71C69402C00C8CFFD37906B1354437B4C8810E"
$managerUrl = "https://github.com/tiann/KernelSU/releases/download/v3.3.0/KernelSU_v3.3.0_32601-release.apk"
$managerSha = "C197060ECB89702E7D54A4C95E29CF5E8D97369BBBB436979AB7FD6BCDE7B077"

$memberHashes = @{
    "kernelsu.ko"  = "7B153982DD1C7354D7DA41689DF8B97DFC24ACA54B467A6A43311071E5643037"
    "ksud"         = "99AAA607E9C9DA6A0E898366ECF0A14DD67224EA726D952D1CE575E62D3B5C41"
    "magiskpolicy" = "9837DB9DB475EB74B6715F081768CB6A1F2FB5A2B2AC15755686062501BACE27"
}

function Resolve-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
    return [IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Path))
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Assert-Sha256 {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Expected
    )
    $actual = Get-Sha256 -Path $Path
    if ($actual -ne $Expected.ToUpperInvariant()) {
        throw "SHA256 mismatch for $Path`nexpected: $Expected`nactual:   $actual"
    }
}

function Download-File {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$OutFile
    )
    Write-Host "== downloading $Uri"
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $OutFile
        return
    } catch {
        $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
        if (-not $curl) { $curl = Get-Command curl -ErrorAction SilentlyContinue }
        if (-not $curl) { throw }
        & $curl.Source -fL --retry 3 --output $OutFile $Uri
        if ($LASTEXITCODE -ne 0) { throw "download failed: $Uri" }
    }
}

$Destination = Resolve-FullPath -Path $Destination
$Cache = Resolve-FullPath -Path $Cache
New-Item -ItemType Directory -Force -Path $Destination, $Cache | Out-Null

$archive = Join-Path $Cache "ghostlock-v0.3.1.tar.gz"
$manager = Join-Path $Destination "KernelSU_v3.3.0_32601-release.apk"

if ($Force -or -not (Test-Path -LiteralPath $archive)) {
    Download-File -Uri $ghostlockUrl -OutFile $archive
}
Assert-Sha256 -Path $archive -Expected $ghostlockSha

if ($Force -or -not (Test-Path -LiteralPath $manager)) {
    Download-File -Uri $managerUrl -OutFile $manager
}
Assert-Sha256 -Path $manager -Expected $managerSha

$extract = Join-Path $Cache ("extract-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $extract | Out-Null
try {
    $tar = Get-Command tar.exe -ErrorAction SilentlyContinue
    if (-not $tar) { $tar = Get-Command tar -ErrorAction SilentlyContinue }
    if (-not $tar) { throw "tar is required to extract ghostlock.tar.gz" }

    & $tar.Source -xzf $archive -C $extract
    if ($LASTEXITCODE -ne 0) { throw "tar extraction failed" }

    $sourceDir = Join-Path $extract "ghostlock"
    foreach ($name in $memberHashes.Keys) {
        $source = Join-Path $sourceDir $name
        if (-not (Test-Path -LiteralPath $source)) { throw "missing bundle member: $name" }
        $target = Join-Path $Destination $name
        Copy-Item -LiteralPath $source -Destination $target -Force
        Assert-Sha256 -Path $target -Expected $memberHashes[$name]
    }
} finally {
    if (Test-Path -LiteralPath $extract) {
        Remove-Item -LiteralPath $extract -Recurse -Force
    }
}

$sums = @(
    "$(Get-Sha256 -Path $manager)  KernelSU_v3.3.0_32601-release.apk"
)
foreach ($name in ($memberHashes.Keys | Sort-Object)) {
    $sums += "$(Get-Sha256 -Path (Join-Path $Destination $name))  $name"
}
[IO.File]::WriteAllLines(
    (Join-Path $Destination "SHA256SUMS"),
    $sums,
    [Text.UTF8Encoding]::new($false)
)

Write-Host "== bundle ready: $Destination"
Write-Host "== verified: kernelsu.ko, ksud, magiskpolicy, KernelSU manager APK"
