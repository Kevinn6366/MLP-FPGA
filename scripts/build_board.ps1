$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Path (Join-Path $projectRoot 'build\board') -Force | Out-Null
Push-Location $projectRoot
try {
    & 'D:\vivado\Vivado\2019.1\bin\vivado.bat' -mode batch -source scripts/build_board.tcl -log build/board/build.log -journal build/board/build.jou
    if($LASTEXITCODE -ne 0){throw 'Board build failed; do not program stale outputs.'}
} finally {Pop-Location}
