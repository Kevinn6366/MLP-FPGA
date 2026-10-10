$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$vivado='D:\vivado\Vivado\2019.1\bin\vivado.bat'
if(!(Test-Path -LiteralPath $vivado)){throw 'Update the Vivado path in scripts/run_sim.ps1 for this computer.'}
New-Item -ItemType Directory -Path (Join-Path $projectRoot 'build') -Force | Out-Null
Push-Location $projectRoot
try {
    & $vivado -mode batch -source scripts/run_sim.tcl -log build/simulation.log -journal build/simulation.jou
    if($LASTEXITCODE -ne 0){throw "Vivado failed: exit $LASTEXITCODE"}
} finally {Pop-Location}
