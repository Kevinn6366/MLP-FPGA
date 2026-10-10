[CmdletBinding()]
param(
    [string]$Tensor,
    [switch]$Rebuild
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$buildRoot = Join-Path $projectRoot 'build\mlp_console'
$toolRoot = 'D:\vivado\Vivado\2019.1\bin'
$singleRequest = $PSBoundParameters.ContainsKey('Tensor')

function Convert-InputTensor([string]$Text) {
    $body = $Text.Trim()
    # Accept [a,b,c,d], [[a,b,c,d]], a,b,c,d, or whitespace-separated values.
    if ($body -match '^\[\s*\[([^\[\]]*)\]\s*\]$') { $body = $Matches[1] }
    elseif ($body -match '^\[([^\[\]]*)\]$') { $body = $Matches[1] }
    if ($body.Contains(',')) {
        $parts = @($body -split ',')
    } else {
        $parts = @($body.Trim() -split '\s+')
    }
    if ($parts.Count -ne 4) { throw 'Enter exactly 4 integers, for example [1,2,3,4].' }
    $values = @()
    foreach ($part in $parts) {
        $number = 0
        if ($part.Trim() -notmatch '^[+-]?[0-9]+$' -or
            ![int]::TryParse($part.Trim(), [ref]$number)) {
            throw 'Only decimal integers are accepted; no floats or expressions.'
        }
        if ($number -lt -128 -or $number -gt 127) {
            throw "Value $number is outside signed int8 range [-128,127]."
        }
        $values += $number
    }
    return ,$values
}

function Invoke-XilinxTool([string]$Tool, [string[]]$ToolArguments, [string]$Capture) {
    # Arguments are passed as data, never evaluated as PowerShell commands.
    $savedPreference = $ErrorActionPreference
    try {
        # Native tools may write warnings to stderr; decide failure by exit code.
        $ErrorActionPreference = 'Continue'
        & (Join-Path $toolRoot $Tool) @ToolArguments > $Capture 2>&1
        $toolExit = $LASTEXITCODE
    } finally { $ErrorActionPreference = $savedPreference }
    if ($toolExit -ne 0) {
        Get-Content -LiteralPath $Capture -Tail 20 | Write-Host
        throw "$Tool failed (exit $toolExit). Log: $Capture"
    }
}

function Initialize-ConsoleSimulation {
    $sources = @('rtl\mlp4.v', 'rtl\mlp4_weights.vh',
                 'sim\tb_mlp_console.sv', 'scripts\mlp_console.ps1')
    $hashes = foreach ($relative in $sources) {
        (Get-FileHash -LiteralPath (Join-Path $projectRoot $relative) -Algorithm SHA256).Hash
    }
    $signature = $toolRoot + ':' + ($hashes -join ':')
    $stampPath = Join-Path $buildRoot 'source_signature.txt'
    $snapshotPath = Join-Path $buildRoot 'xsim.dir\mlp_console\xsimk.exe'
    if (!$Rebuild -and (Test-Path -LiteralPath $stampPath) -and
        (Test-Path -LiteralPath $snapshotPath) -and
        ([IO.File]::ReadAllText($stampPath).Trim() -eq $signature)) {
        return
    }
    Write-Host 'Compiling Verilog RTL with Vivado Simulator...' -ForegroundColor Cyan
    # Invalidate first: a failed build must never be treated as a cached success.
    [IO.File]::WriteAllText($stampPath, '')
    Invoke-XilinxTool 'xvlog.bat' @('--work','xil_defaultlib','--include',
        (Join-Path $projectRoot 'rtl'), (Join-Path $projectRoot 'rtl\mlp4.v'),
        '--log','compile_rtl.log') 'compile_rtl_console.log'
    Invoke-XilinxTool 'xvlog.bat' @('--sv','--work','xil_defaultlib',
        (Join-Path $projectRoot 'sim\tb_mlp_console.sv'),
        '--log','compile_tb.log') 'compile_tb_console.log'
    Invoke-XilinxTool 'xelab.bat' @('xil_defaultlib.tb_mlp_console',
        '--snapshot','mlp_console','--debug','typical','--mt','2',
        '--log','elaborate.log') 'elaborate_console.log'
    if (!(Test-Path -LiteralPath $snapshotPath)) { throw 'Compiled simulation snapshot is missing.' }
    [IO.File]::WriteAllText($stampPath, $signature)
    $script:Rebuild = $false
    Write-Host 'Compilation complete. Subsequent tensors reuse this snapshot.' -ForegroundColor Green
}

function Invoke-Tensor([int[]]$Values) {
    Initialize-ConsoleSimulation
    $hexBytes = foreach ($index in 3,2,1,0) { '{0:x2}' -f ($Values[$index] -band 255) }
    $hexTensor = $hexBytes -join ''
    # Explicit quotes preserve '=' through the Xilinx Windows batch wrappers.
    $plusArg = '"X=' + $hexTensor + '"'
    Invoke-XilinxTool 'xsim.bat' @('mlp_console','--runall','--onerror','quit',
        '--onfinish','quit','--testplusarg',$plusArg,'--log','last_simulation.log') 'last_console.log'
    $result = @(Get-Content -LiteralPath 'last_console.log' | Where-Object { $_ -match '^RESULT input=' })
    if ($result.Count -ne 1) {
        Get-Content -LiteralPath 'last_console.log' -Tail 20 | Write-Host
        throw 'Simulation did not produce exactly one valid result.'
    }
    $inputPattern = [regex]::Escape('RESULT input=[' + ($Values -join ',') + ']')
    if ($result[0] -notmatch ("^" + $inputPattern + ' output=\[-?[0-9]+,-?[0-9]+\] cycles=229$')) {
        throw 'Simulation result does not match the submitted request or expected latency.'
    }
    Write-Host $result[0] -ForegroundColor Green
}

$lockStream = $null
$locationPushed = $false
try {
    # Validate a one-shot input before compiling or invoking the simulator.
    if ($singleRequest) { $oneTensor = Convert-InputTensor $Tensor }
    foreach ($tool in 'xvlog.bat','xelab.bat','xsim.bat') {
        if (!(Test-Path -LiteralPath (Join-Path $toolRoot $tool))) {
            throw "Missing $tool. Update toolRoot in this script for this computer."
        }
    }
    New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
    try {
        $lockStream = [IO.File]::Open((Join-Path $buildRoot 'session.lock'),
            [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    } catch { throw 'Another MLP console is using this build folder. Exit it first.' }
    Push-Location -LiteralPath $buildRoot
    $locationPushed = $true
    if ($singleRequest) {
        Invoke-Tensor $oneTensor
    } else {
        Write-Host 'MLP 4->8->8->8->2 | Verilog RTL simulation | no Python' -ForegroundColor Cyan
        Write-Host 'Enter 4 signed integers [-128,127], e.g. [1,2,3,4]. Type q to quit.'
        while ($true) {
            $line = Read-Host 'Tensor [1,4]'
            if ($null -eq $line -or $line.Trim() -in @('q','quit','exit')) { break }
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try { $values = Convert-InputTensor $line }
            catch { Write-Host $_.Exception.Message -ForegroundColor Yellow; continue }
            Invoke-Tensor $values
        }
    }
} catch {
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
} finally {
    if ($locationPushed) { Pop-Location }
    if ($null -ne $lockStream) { $lockStream.Dispose() }
}
