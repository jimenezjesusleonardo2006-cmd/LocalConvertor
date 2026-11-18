param(
    [switch]$SkipTests
)

$ErrorActionPreference = "Stop"

$RootDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$RustDir = Join-Path $RootDir "rust"
$DistDir = Join-Path $RootDir "dist"
$ReleaseDir = Join-Path $RootDir "build\windows\x64\runner\Release"
$IssPath = Join-Path $RootDir "installer\local_convert_setup.iss"
$PortableZip = Join-Path $DistDir "LocalConvert_v1.0.0_Portable_Win64.zip"

$CargoBin = Join-Path $env:USERPROFILE ".cargo\bin"
if (Test-Path $CargoBin) {
    $env:Path = "$CargoBin;" + $env:Path
}

Write-Host "==> [1/4] Compilando motor nativo Rust (local_convert_core.dll)..." -ForegroundColor Cyan
Push-Location $RustDir
try {
    & cargo test --release
    if ($LASTEXITCODE -ne 0) { throw "Fallo en cargo test --release" }
    & cargo build --release
    if ($LASTEXITCODE -ne 0) { throw "Fallo en cargo build --release" }
} finally {
    Pop-Location
}

if (-not $SkipTests) {
    Write-Host "==> [2/4] Ejecutando pruebas unitarias y de widgets en Flutter..." -ForegroundColor Cyan
    Push-Location $RootDir
    try {
        & flutter analyze
        if ($LASTEXITCODE -ne 0) { throw "Fallo en flutter analyze" }
        & flutter test
        if ($LASTEXITCODE -ne 0) { throw "Fallo en flutter test" }
    } finally {
        Pop-Location
    }
}

Write-Host "==> [3/4] Compilando LocalConvert Release para Windows x64..." -ForegroundColor Cyan
Push-Location $RootDir
try {
    & flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "Fallo en flutter build windows --release" }
} finally {
    Pop-Location
}

if (-not (Test-Path (Join-Path $ReleaseDir "local_convert.exe"))) {
    throw "No se generó local_convert.exe en $ReleaseDir"
}

New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
if (Test-Path $PortableZip) {
    Remove-Item $PortableZip -Force
}

Write-Host "==> [4/4] Generando paquete Portable (.ZIP) e Instalador (.EXE)..." -ForegroundColor Cyan
Compress-Archive -Path (Join-Path $ReleaseDir "*") -DestinationPath $PortableZip -CompressionLevel Optimal
Write-Host "    Portable ZIP listo: $PortableZip" -ForegroundColor Green

$IsccCandidates = @(
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
)
$IsccExe = $IsccCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($IsccExe) {
    & $IsccExe $IssPath
    if ($LASTEXITCODE -ne 0) { throw "Fallo compilando el instalador Inno Setup" }
    Write-Host "    Instalador listo: $(Join-Path $DistDir 'LocalConvert_v1.0.0_Setup.exe')" -ForegroundColor Green
} else {
    Write-Warning "ISCC.exe (Inno Setup 6) no encontrado. Para instalarlo y compilar el instalador ejecuta:"
    Write-Host "    winget install JRSoftware.InnoSetup" -ForegroundColor Yellow
}
