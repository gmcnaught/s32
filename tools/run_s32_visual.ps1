# Launch the native System 32 visual Verilator model and its live Tk window.

[CmdletBinding()]
param(
    [ValidatePattern("^[a-zA-Z0-9_]+$")]
    [string]$Game = "ga2",
    [string]$ModelDirectory = "scratch\s32_obj_s32_visual",
    [string]$OutputDirectory = "",
    [int]$Frames = 1000000,
    [string]$Save = "",
    [int]$AutoSaveFrame = 200,
    [string]$Restore = "",
    [string[]]$SimulationArgs = @(),
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
$liveFile = Join-Path $OutputDirectory "live.ppm"
$inputFile = Join-Path $OutputDirectory "input.txt"
$stdout = Join-Path $OutputDirectory "simulator.stdout.log"
$stderr = Join-Path $OutputDirectory "simulator.stderr.log"
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$imageDirectory = Join-Path $Root ("roms\sim\" + $Game)
$descriptor = Join-Path $imageDirectory "desc.txt"
$executable = Join-Path $ModelDirectory "s32_visual.exe"
foreach ($required in @($descriptor, (Join-Path $imageDirectory "maincpu.hex"), $executable)) {
    if (-not (Test-Path -LiteralPath $required)) {
        if ($required -eq $executable -and -not $NoBuild) { continue }
        throw "Missing visual input: $required"
    }
}

# The mandatory visible frontend starts before any Verilator build/version
# operation and remains open throughout both compilation and simulation.
$sdlSource = Join-Path $Root "verif\visual\s32_sdl_viewer.cpp"
$sdlExe = Join-Path $Root "scratch\s32_sdl_viewer.exe"
$gxx = "C:\msys64\ucrt64\bin\g++.exe"
if (-not (Test-Path -LiteralPath $sdlExe) -or
    (Get-Item -LiteralPath $sdlSource).LastWriteTimeUtc -gt (Get-Item -LiteralPath $sdlExe).LastWriteTimeUtc) {
    $savedPath = $env:PATH
    try {
        $env:PATH = "C:\msys64\ucrt64\bin;" + $env:PATH
        & $gxx -std=c++17 -O2 -mwindows -I C:\msys64\ucrt64\include\SDL2 `
            $sdlSource -o $sdlExe -L C:\msys64\ucrt64\lib -lSDL2
        if ($LASTEXITCODE -ne 0) { throw "SDL viewer build failed with exit code $LASTEXITCODE" }
    }
    finally { $env:PATH = $savedPath }
}
$sdlDll = Join-Path (Split-Path $sdlExe) "SDL2.dll"
if (-not (Test-Path -LiteralPath $sdlDll)) {
    Copy-Item -LiteralPath "C:\msys64\ucrt64\bin\SDL2.dll" -Destination $sdlDll
}
$window = Start-Process -FilePath $sdlExe -ArgumentList @($liveFile, $inputFile) -PassThru
Start-Sleep -Milliseconds 500
if ($window.HasExited) { throw "Visible SDL viewer exited before Verilator launch" }

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
if (-not $Save) { $Save = Join-Path $OutputDirectory ("{0}-preinput.vltsv" -f $Game) }
$Save = [IO.Path]::GetFullPath($Save)
$simArgs += "+SAVE=$Save", "+AUTOSAVEFRAME=$AutoSaveFrame"
if ($Restore) { $simArgs += "+RESTORE=$([IO.Path]::GetFullPath($Restore))" }
$simArgs += $SimulationArgs
$simParameters = @{
    FilePath = $SafeSim
    ArgumentList = $simArgs
    WorkingDirectory = $OutputDirectory
    RedirectStandardOutput = $stdout
    RedirectStandardError = $stderr
    PassThru = $true
}
$sim = Start-Process @simParameters
Write-Host "VISUAL LAUNCH PASS"
Write-Host "Game: $Game"
Write-Host "Simulator PID: $($sim.Id)"
Write-Host "Viewer PID: $($window.Id)"
Write-Host "Frame file: $liveFile"
Write-Host "Checkpoint: $Save (automatic at frame $AutoSaveFrame)"
Write-Host "Keyboard: arrows move, Z/X/C are buttons, 5=coin, 6=start, Escape closes the SDL viewer"

if (-not $Detached) {
    Wait-Process -Id $sim.Id
    if ($sim.ExitCode -ne 0) { throw "Visual simulator exited with code $($sim.ExitCode)" }
}
