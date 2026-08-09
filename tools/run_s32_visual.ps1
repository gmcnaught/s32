# Launch the native System 32 visual Verilator model and its live Tk window.

[CmdletBinding()]
param(
    [ValidatePattern("^[a-zA-Z0-9_]+$")]
    [string]$Game = "ga2",
    [string]$ModelDirectory = "scratch\s32_obj_s32_visual",
    [string]$OutputDirectory = "",
    [int]$Frames = 1000000,
    [switch]$Detached,
    [switch]$NoBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$BuildScript = Join-Path $Root "tools\build_s32_visual.ps1"
$SafeSim = "C:\Users\meath\bin\verilator-sim-safe.exe"
if (-not (Test-Path -LiteralPath $SafeSim)) {
    $command = Get-Command "verilator-sim-safe.exe" -ErrorAction SilentlyContinue
    if ($command) { $SafeSim = $command.Source }
}
if (-not (Test-Path -LiteralPath $SafeSim)) { throw "verilator-sim-safe.exe was not found" }

$ModelDirectory = [IO.Path]::GetFullPath($ModelDirectory)
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $Root ("scratch\s32_visual\" + $Game) }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$imageDirectory = Join-Path $Root ("roms\sim\" + $Game)
$descriptor = Join-Path $imageDirectory "desc.txt"
$executable = Join-Path $ModelDirectory "s32_visual.exe"
foreach ($required in @($descriptor, (Join-Path $imageDirectory "maincpu.hex"), $executable)) {
    if (-not (Test-Path -LiteralPath $required)) {
        if ($required -eq $executable -and -not $NoBuild) { continue }
        throw "Missing visual input: $required"
    }
}

if (-not $NoBuild) {
    & $BuildScript -ModelDirectory $ModelDirectory
}
if (-not (Test-Path -LiteralPath $executable)) { throw "Missing visual executable: $executable" }

# Keep the model on the same UCRT64 ABI it was built against.  The safe
# launcher may sanitize PATH, so executable-local runtime DLLs are deliberate.
foreach ($runtimeDll in @("libgcc_s_seh-1.dll", "libstdc++-6.dll", "libwinpthread-1.dll")) {
    $runtimeSource = Join-Path "C:\msys64\ucrt64\bin" $runtimeDll
    if (-not (Test-Path -LiteralPath $runtimeSource)) {
        throw "Missing UCRT64 runtime DLL: $runtimeSource"
    }
    Copy-Item -LiteralPath $runtimeSource -Destination $ModelDirectory -Force
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

$liveFile = Join-Path $OutputDirectory "live.ppm"
$statusFile = Join-Path $OutputDirectory "viewer_status.json"
$inputFile = Join-Path $OutputDirectory "input.txt"
$stdout = Join-Path $OutputDirectory "simulator.stdout.log"
$stderr = Join-Path $OutputDirectory "simulator.stderr.log"
$viewer = Join-Path $Root "verif\visual\s32_frame_viewer.py"
$python = (Get-Command "python.exe" -ErrorAction SilentlyContinue)
if (-not $python) { $python = Get-Command "python" -ErrorAction SilentlyContinue }
if (-not $python) { throw "Python is required for the native Tk viewer" }

& $SafeSim status
$simArgs = @(
    "--", $executable,
    "+IMG=$imageDirectory",
    "+DESC=$descriptor",
    "+FRAMES=$Frames",
    "+LIVEPPM=$liveFile",
    "+INPUTFILE=$inputFile",
    "+QUIET"
)
$simParameters = @{
    FilePath = $SafeSim
    ArgumentList = $simArgs
    WorkingDirectory = $OutputDirectory
    RedirectStandardOutput = $stdout
    RedirectStandardError = $stderr
    PassThru = $true
}
$sim = Start-Process @simParameters
$viewerArgs = @($viewer, $OutputDirectory, "--live-file", $liveFile, "--status", $statusFile,
                "--input", $inputFile)
$viewerParameters = @{
    FilePath = $python.Source
    ArgumentList = $viewerArgs
    WorkingDirectory = $OutputDirectory
    PassThru = $true
}
$window = Start-Process @viewerParameters

Write-Host "VISUAL LAUNCH PASS"
Write-Host "Game: $Game"
Write-Host "Simulator PID: $($sim.Id)"
Write-Host "Viewer PID: $($window.Id)"
Write-Host "Frame file: $liveFile"
Write-Host "Checkpoint: disabled explicitly (S32_VISUAL_NO_SAVE; timing testbench is not savable)"
Write-Host "Keyboard: arrows move, Z/X/C are buttons, 5=coin, 6=start, Escape closes the viewer"

if (-not $Detached) {
    Wait-Process -Id $sim.Id
    if ($sim.ExitCode -ne 0) { throw "Visual simulator exited with code $($sim.ExitCode)" }
}
