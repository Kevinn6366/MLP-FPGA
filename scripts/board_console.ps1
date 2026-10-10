[CmdletBinding()]
param([string]$Tensor)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$toolRoot='D:\vivado\Vivado\2019.1\bin'
$boardBuild=Join-Path $projectRoot 'build\board'
$singleRequest=$PSBoundParameters.ContainsKey('Tensor')

function Convert-BoardInput([string]$Text) {
    $body=$Text.Trim()
    if($body -match '^\[\s*\[([^\[\]]*)\]\s*\]$'){$body=$Matches[1]}
    elseif($body -match '^\[([^\[\]]*)\]$'){$body=$Matches[1]}
    if($body.Contains(',')){$parts=@($body -split ',')}
    else {$parts=@($body.Trim() -split '\s+')}
    if($parts.Count -ne 4){throw 'Enter exactly four signed integers, e.g. [1,2,3,4].'}
    $values=@()
    foreach($part in $parts){
        $value=0
        if($part.Trim() -notmatch '^[+-]?[0-9]+$' -or ![int]::TryParse($part.Trim(),[ref]$value)){
            throw 'Only decimal integers are accepted.'
        }
        if($value -lt -128 -or $value -gt 127){throw 'Input range is [-128,127].'}
        $values+=$value
    }
    return ,$values
}

function Test-HardwareServer {
    $client=New-Object Net.Sockets.TcpClient
    try {
        $pending=$client.BeginConnect('127.0.0.1',3121,$null,$null)
        if(!$pending.AsyncWaitHandle.WaitOne(500)){return $false}
        $client.EndConnect($pending)
        return $true
    } catch {return $false}
    finally {$client.Close()}
}

function Start-HardwareServer {
    if(Test-HardwareServer){return}
    $serverPath=Join-Path $toolRoot 'hw_server.bat'
    if(!(Test-Path -LiteralPath $serverPath)){throw 'Vivado hardware server is missing.'}
    $command="& '$serverPath' -s tcp::3121"
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -ArgumentList @('-NoProfile','-EncodedCommand',$encoded) -WindowStyle Hidden | Out-Null
    for($attempt=0;$attempt -lt 30;$attempt++){
        Start-Sleep -Milliseconds 500
        if(Test-HardwareServer){return}
    }
    throw 'Hardware server did not start on 127.0.0.1:3121.'
}

function Invoke-BoardTensor([int[]]$Values){
    $bytes=foreach($i in 3,2,1,0){'{0:x2}' -f ($Values[$i] -band 255)}
    $hex=$bytes -join ''
    $timer=[Diagnostics.Stopwatch]::StartNew()
    Write-Host ('输入张量 ['+($Values -join ',')+'] → FPGA PL') -ForegroundColor Cyan
    Write-Host '[0.0s] 检查本机 JTAG 服务...'
    Start-HardwareServer
    Write-Host ('[{0:F1}s] 启动 Vivado 硬件工具，请稍候...' -f $timer.Elapsed.TotalSeconds)
    $labels=@{
        CONNECT='连接硬件服务'; TARGET='打开板卡 JTAG'; PROBES='读取调试探针';
        READY='板上推理电路就绪'; RESET='复位推理状态'; INPUT='输入张量已写入';
        IDLE='确认时钟锁定、计算空闲'; REQUEST='触发四层推理';
        DONE='FPGA 已完成计算'; READ='读取输出张量';
        CLOSE='释放 JTAG，等待工具退出'; CLOSED='JTAG 已关闭，等待工具进程结束'
    }
    $logPath=Join-Path $boardBuild 'last_request_console.log'
    $writer=New-Object IO.StreamWriter($logPath,$false,[Text.UTF8Encoding]::new($false))
    $writer.AutoFlush=$true
    $results=New-Object 'System.Collections.Generic.List[string]'
    $savedPreference=$ErrorActionPreference
    try {
        $ErrorActionPreference='Continue'
        & (Join-Path $toolRoot 'vivado.bat') -mode batch -notrace -source (Join-Path $PSScriptRoot 'board_infer.tcl') `
            -log (Join-Path $boardBuild 'last_request.log') -journal (Join-Path $boardBuild 'last_request.jou') `
            -tclargs $hex 2>&1 | ForEach-Object {
                $line=$_.ToString()
                $writer.WriteLine($line)
                if($line -match '^BOARD_LOG: ([A-Z]+)\s*(.*)$'){
                    $event=$Matches[1]; $detail=$Matches[2]
                    $label=$labels[$event]
                    if(!$label){$label=$event}
                    Write-Host ('[{0:F1}s] {1} {2}' -f $timer.Elapsed.TotalSeconds,$label,$detail)
                } elseif($line -match '^BOARD_RESULT '){
                    $results.Add($line)
                    Write-Host $line -ForegroundColor Green
                } elseif($line -match '^(ERROR:|CRITICAL WARNING:|WARNING:)'){
                    Write-Host $line -ForegroundColor Yellow
                }
            }
        $code=$LASTEXITCODE
    } finally {$ErrorActionPreference=$savedPreference; $writer.Dispose()}
    if($code -ne 0){
        Get-Content -LiteralPath $logPath -Tail 15 | Write-Host
        throw 'Board request failed. Check board power/USB and program the MLP bitstream.'
    }
    if($results.Count -ne 1 -or $results[0] -notmatch "^BOARD_RESULT x=$hex output=\[-?[0-9]+,-?[0-9]+\] source=FPGA_PL clock=25MHz$"){
        throw 'No matching actual-board result was returned.'
    }
    Write-Host ('完成：主机总耗时 {0:F1}s（含工具启动/JTAG），完整日志：build\board\last_request_console.log' -f $timer.Elapsed.TotalSeconds)
}

$lockStream=$null
$pushed=$false
try {
    if($singleRequest){$values=Convert-BoardInput $Tensor}
    if(!(Test-Path -LiteralPath (Join-Path $boardBuild 'mlp_board.ltx'))){throw 'Build and program the board design first.'}
    try {
        $lockStream=[IO.File]::Open((Join-Path $boardBuild 'console.lock'),
            [IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    } catch {throw 'Another board console is active. Exit it first.'}
    Push-Location $boardBuild
    $pushed=$true
    if($singleRequest){Invoke-BoardTensor $values}
    else {
        Write-Host '真实 FPGA PL | Zybo Z7-20 | MLP 4->8->8->8->2 | 25MHz' -ForegroundColor Cyan
        Write-Host '输入四个 -128～127 的整数，例如 [1,2,3,4]；q 退出。计算在板子上完成。'
        while($true){
            $line=Read-Host '输入张量 [1,4]'
            if($null -eq $line -or $line.Trim() -in @('q','quit','exit')){break}
            if([string]::IsNullOrWhiteSpace($line)){continue}
            try {$values=Convert-BoardInput $line}
            catch {Write-Host $_.Exception.Message -ForegroundColor Yellow; continue}
            Invoke-BoardTensor $values
        }
    }
} catch {
    Write-Host ('ERROR: '+$_.Exception.Message) -ForegroundColor Red
    exit 1
} finally {
    if($pushed){Pop-Location}
    if($null -ne $lockStream){$lockStream.Dispose()}
}
