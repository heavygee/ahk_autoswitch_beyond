Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceAhk = Join-Path $repoRoot "autoswitch mic for VR.ahk"
$sourceExe = Join-Path $repoRoot "autoswitch mic for VR.exe"
$iconPath = Join-Path $repoRoot "images\beyond_nvidia.ico"
$compiler = "C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe"
$baseFile = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
$runtimeDir = "C:\Users\HeavyGee\Documents\AutoHotkey"
$runtimeExe = Join-Path $runtimeDir "autoswitch mic for VR.exe"

if (-not (Test-Path $compiler)) {
    throw "Ahk2Exe not found at '$compiler'."
}
if (-not (Test-Path $sourceAhk)) {
    throw "Source script missing at '$sourceAhk'."
}
if (-not (Test-Path $iconPath)) {
    throw "Icon file missing at '$iconPath'."
}
if (-not (Test-Path $runtimeDir)) {
    throw "Runtime directory missing at '$runtimeDir'."
}
if (-not (Test-Path $baseFile)) {
    throw "AutoHotkey v2 base executable missing at '$baseFile'."
}

Write-Host "Compiling EXE with icon..."
& $compiler /in $sourceAhk /out $sourceExe /icon $iconPath /base $baseFile /silent verbose
$exitVar = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
$compileExit = if ($null -ne $exitVar) { [int]$exitVar.Value } else { 0 }
if ($compileExit -ne 0) {
    throw "Ahk2Exe failed with exit code $compileExit."
}

# Ahk2Exe can report success just before filesystem metadata settles.
$maxChecks = 10
$created = $false
for ($i = 0; $i -lt $maxChecks; $i++) {
    if (Test-Path $sourceExe) {
        $created = $true
        break
    }
    Start-Sleep -Milliseconds 200
}
if (-not $created) {
    throw "Expected output EXE was not created at '$sourceExe'."
}

Write-Host "Stopping existing runtime instance (if running)..."
$running = Get-Process -Name "autoswitch mic for VR" -ErrorAction SilentlyContinue
if ($running) {
    $running | Stop-Process -Force
    Start-Sleep -Milliseconds 350
}

Write-Host "Stopping matching AutoHotkey interpreter instance (if running)..."
$ahkProcs = Get-CimInstance Win32_Process -Filter "Name = 'AutoHotkey.exe' OR Name = 'AutoHotkey64.exe' OR Name = 'AutoHotkey32.exe'" |
    Where-Object { $_.CommandLine -like "*autoswitch mic for VR.ahk*" }
if ($ahkProcs) {
    $ahkProcs | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    Start-Sleep -Milliseconds 350
}

Write-Host "Copying EXE to runtime directory..."
Copy-Item $sourceExe $runtimeExe -Force

Write-Host "Launching runtime EXE from C: path..."
Start-Process -FilePath $runtimeExe -WorkingDirectory $runtimeDir

Write-Host "Done."
