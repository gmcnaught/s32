$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Resolve-Path (Join-Path $here '..\..')
$work = Join-Path $here 'work'
New-Item -ItemType Directory -Force $work | Out-Null
Push-Location $work
try {
    python -B (Join-Path $here 'gen_vectors.py') (Join-Path $work 'vectors.txt') (Join-Path $work 'branches.txt')
    ghdl -a --std=08 (Join-Path $root 'rtl\cpu\upd7725\upd7725_lab.vhd') (Join-Path $here 'tb_upd7725_lab.vhd')
    if ($LASTEXITCODE) { throw "GHDL analysis failed" }
    ghdl -a --std=08 (Join-Path $here 'tb_upd7725_vectors.vhd')
    ghdl -e --std=08 tb_upd7725_lab
    ghdl -r --std=08 tb_upd7725_lab --assert-level=error
    if ($LASTEXITCODE) { throw "focused GHDL simulation failed" }
    ghdl -e --std=08 tb_upd7725_vectors
    $vectors = Join-Path $work 'vectors.txt'
    $branches = Join-Path $work 'branches.txt'
    ghdl -r --std=08 tb_upd7725_vectors "-gVECTOR_FILE=$vectors" "-gBRANCH_FILE=$branches" --assert-level=error
    if ($LASTEXITCODE) { throw "vector GHDL simulation failed" }
    python -B -m unittest discover -s $here -p 'test_converter.py'
    if ($LASTEXITCODE) { throw "Python tests failed" }
} finally { Pop-Location }
