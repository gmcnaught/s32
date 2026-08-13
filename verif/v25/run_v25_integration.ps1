[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$msysBash = 'C:\msys64\usr\bin\bash.exe'
if (-not (Test-Path -LiteralPath $msysBash -PathType Leaf)) {
    throw 'MSYS2 bash is required for the native Windows V25 integration runner.'
}

$taskTemp = Join-Path $repoRoot 'scratch\tmp'
$buildDir = $null
$validatedBuildDir = $false
$savedPath = $env:PATH
$savedSafe = $env:S32_VERILATOR_SAFE
$savedSimSafe = $env:S32_VERILATOR_SIM_SAFE
$savedBuildOnly = $env:S32_V25_BUILD_ONLY
$savedKeepBuild = $env:KEEP_BUILD
try {
    New-Item -ItemType Directory -Force -Path $taskTemp | Out-Null
    $env:PATH = 'C:\msys64\ucrt64\bin;C:\msys64\usr\bin;C:\Users\meath\bin;' + $savedPath
    $safeVerilator = (Get-Command verilator-safe -ErrorAction Stop).Source
    $safeSimulator = (Get-Command verilator-sim-safe -ErrorAction Stop).Source
    $env:S32_VERILATOR_SAFE = ($safeVerilator -replace '\\', '/')
    $env:S32_VERILATOR_SIM_SAFE = ($safeSimulator -replace '\\', '/')
    $env:S32_V25_BUILD_ONLY = '1'
    $env:KEEP_BUILD = '1'
    $script = ($repoRoot -replace '\\', '/') + '/verif/v25/run_v25_integration.sh'

    [string[]]$buildOutput = & $msysBash -lc $script 2>&1
    $buildExitCode = $LASTEXITCODE
    $buildOutput | ForEach-Object { Write-Output $_ }
    if ($buildExitCode -ne 0) {
        throw "V25 integration build failed with exit code $buildExitCode."
    }

    $exePrefix = 'V25_INTEGRATION EXE: '
    $dirPrefix = 'V25_INTEGRATION BUILD DIR: '
    $exeLine = $buildOutput | Where-Object { $_.StartsWith($exePrefix) } | Select-Object -Last 1
    $dirLine = $buildOutput | Where-Object { $_.StartsWith($dirPrefix) } | Select-Object -Last 1
    if (-not $exeLine -or -not $dirLine) {
        throw 'V25 integration build did not report its executable and build directory.'
    }

    $firmwareExe = [IO.Path]::GetFullPath($exeLine.Substring($exePrefix.Length).Trim())
    $buildDir = [IO.Path]::GetFullPath($dirLine.Substring($dirPrefix.Length).Trim()).TrimEnd('\')
    $scratchRoot = [IO.Path]::GetFullPath($taskTemp).TrimEnd('\')
    $expectedExe = Join-Path $buildDir 'obj_dir\Vtb_core_v25int.exe'
    if (-not $buildDir.StartsWith($scratchRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
        -not (Split-Path -Leaf $buildDir).StartsWith('s32-v25int.', [StringComparison]::Ordinal) -or
        -not $firmwareExe.Equals($expectedExe, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing an unexpected V25 integration build path: $buildDir"
    }
    $validatedBuildDir = $true
    if (-not (Test-Path -LiteralPath $firmwareExe -PathType Leaf)) {
        throw "V25 integration executable was not produced: $firmwareExe"
    }

    [string[]]$runOutput = & $safeSimulator -- $firmwareExe 2>&1
    $runExitCode = $LASTEXITCODE
    $runOutput | ForEach-Object { Write-Output $_ }
    if ($runExitCode -ne 0) {
        throw "V25 integration simulation failed with exit code $runExitCode."
    }
    if (-not ($runOutput | Where-Object { $_.Contains('V25 INTEGRATION PASS') })) {
        throw 'V25 integration simulation completion marker is missing.'
    }
    Write-Output 'V25_INTEGRATION RUNNER: PASS'
}
finally {
    $env:PATH = $savedPath
    $env:S32_VERILATOR_SAFE = $savedSafe
    $env:S32_VERILATOR_SIM_SAFE = $savedSimSafe
    $env:S32_V25_BUILD_ONLY = $savedBuildOnly
    $env:KEEP_BUILD = $savedKeepBuild
    if ($validatedBuildDir -and (Test-Path -LiteralPath $buildDir)) {
        Remove-Item -LiteralPath $buildDir -Recurse -Force
    }
    elseif ($buildDir -and (Test-Path -LiteralPath $buildDir)) {
        Write-Warning "Retained unvalidated V25 integration build directory: $buildDir"
    }
}
