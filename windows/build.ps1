# build.ps1 — Claudario Windows build script
# Usage:
#   .\build.ps1           # Release build
#   .\build.ps1 -Debug    # Debug build (faster compile)

param([switch]$Debug)

$dotnet = "dotnet"
# Fallback to known install path if dotnet isn't in PATH
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    $dotnet = "C:\Program Files\dotnet\dotnet.exe"
}

$config = if ($Debug) { "Debug" } else { "Release" }
$proj   = "$PSScriptRoot\Claudario.Windows\Claudario.Windows.csproj"

Write-Host "Building Claudario.Windows ($config)..." -ForegroundColor Cyan

& $dotnet build $proj -c $config
if ($LASTEXITCODE -ne 0) { Write-Error "Build failed"; exit 1 }

$outDir = "$PSScriptRoot\Claudario.Windows\bin\$config\net8.0-windows"
Write-Host ""
Write-Host "Done. Run:" -ForegroundColor Green
Write-Host "  $outDir\Claudario.exe"
