param(
  [switch]$Test,
  [switch]$Package
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

$ToolId = "tool-test-notes-summarizer-12345678"
$Version = "1.0.0"

function Get-PlatformKey {
  if ($IsMacOS) {
    if ([System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture -eq "Arm64") {
      return "darwin-arm64"
    }
    return "darwin-x86_64"
  }
  if ($IsLinux) {
    if ([System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture -eq "Arm64") {
      return "linux-aarch64"
    }
    return "linux-x86_64"
  }
  return "windows-x86_64"
}

Write-Host "Building Notes Summarizer binary..." -ForegroundColor Cyan

if (-not (Get-Command pyinstaller -ErrorAction SilentlyContinue)) {
  python -m pip install pyinstaller | Out-Null
}

Remove-Item -Recurse -Force dist, build -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force dist | Out-Null

$SdkPath = Join-Path $ScriptDir "..\..\sdk\python"
$env:PYTHONPATH = $SdkPath

pyinstaller `
  --onefile `
  --name $ToolId `
  --clean `
  --noupx `
  --hidden-import executa_sdk `
  --hidden-import executa_sdk.sampling `
  --paths $SdkPath `
  notes_summarizer.py

$Platform = Get-PlatformKey
$BinaryName = if ($Platform -like "windows-*") { "$ToolId.exe" } else { $ToolId }
$BuiltBinary = Join-Path dist $BinaryName

if (-not (Test-Path $BuiltBinary)) {
  throw "Build failed: $BuiltBinary not found"
}

Write-Host "Built $BuiltBinary for platform $Platform" -ForegroundColor Green

if ($Test) {
  Write-Host "Running describe smoke test..." -ForegroundColor Cyan
  $resp = '{"jsonrpc":"2.0","method":"describe","id":1}' | & $BuiltBinary 2>$null
  $parsed = $resp | ConvertFrom-Json
  if ($parsed.result.name -ne $ToolId) {
    throw "describe smoke test failed"
  }
  Write-Host "describe smoke test passed" -ForegroundColor Green
}

if ($Package) {
  $PkgDir = Join-Path dist "packages"
  New-Item -ItemType Directory -Force $PkgDir | Out-Null

  $Manifest = @{
    name = $ToolId
    version = $Version
    runtime = @{
      binary = @{
        entrypoint = @{
          default = $BinaryName
          "windows-x86_64" = "$ToolId.exe"
        }
        permissions = @{
          "$BinaryName" = "0o755"
        }
      }
    }
  } | ConvertTo-Json -Depth 6

  $Stage = Join-Path dist "stage-$Platform"
  New-Item -ItemType Directory -Force $Stage | Out-Null
  Copy-Item $BuiltBinary (Join-Path $Stage $BinaryName)
  $Manifest | Set-Content (Join-Path $Stage "manifest.json") -Encoding UTF8

  if ($Platform -like "windows-*") {
    $Archive = Join-Path $PkgDir "$ToolId-$Platform.zip"
    if (Test-Path $Archive) { Remove-Item $Archive }
    Compress-Archive -Path (Join-Path $Stage "*") -DestinationPath $Archive
  } else {
    $Archive = Join-Path $PkgDir "$ToolId-$Platform.tar.gz"
    if (Test-Path $Archive) { Remove-Item $Archive }
    tar -czf $Archive -C $Stage .
  }

  Write-Host "Package: $Archive" -ForegroundColor Green
}

Write-Host "Done." -ForegroundColor Cyan
