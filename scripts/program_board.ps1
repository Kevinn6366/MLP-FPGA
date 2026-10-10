$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    # Start a local hardware server if the board console has not already done so.
    $client=New-Object Net.Sockets.TcpClient
    $listening=$false
    try {
        $pending=$client.BeginConnect('127.0.0.1',3121,$null,$null)
        if($pending.AsyncWaitHandle.WaitOne(500)){$client.EndConnect($pending); $listening=$true}
    } catch {} finally {$client.Close()}
    if(!$listening){
        $command="& 'D:\vivado\Vivado\2019.1\bin\hw_server.bat' -s tcp::3121"
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList @('-NoProfile','-EncodedCommand',$encoded) -WindowStyle Hidden | Out-Null
        Start-Sleep -Seconds 3
    }
    & 'D:\vivado\Vivado\2019.1\bin\vivado.bat' -mode batch -notrace -source scripts/program_board.tcl -log build/board/program.log -journal build/board/program.jou
    if($LASTEXITCODE -ne 0){throw 'Board programming or initialization failed.'}
} finally {Pop-Location}
