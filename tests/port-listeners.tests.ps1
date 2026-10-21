$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../engine/scripts/common-windows.ps1')
function Assert($value,$message){if(-not $value){throw $message}}
# Discovery must work without loading the slow NetTCPIP CIM provider.
function Get-NetTCPConnection {throw 'NetTCPIP provider is unavailable'}
function Get-CimInstance {throw 'CIM provider is unavailable'}
$self=[Diagnostics.Process]::GetCurrentProcess()
$codex=[pscustomobject]@{Executable=$self.MainModule.FileName}
$self.Dispose()
foreach($address in @('127.0.0.1','::1','0.0.0.0','::')){
  $listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Parse($address),0)
  try{
    $listener.Start()
    $port=$listener.LocalEndpoint.Port
    $rows=@(Get-DreamSkinPortListeners $port)
    Assert ($rows.Count -eq 1) 'Listener discovery returned an unexpected number of rows'
    Assert ($rows[0].LocalAddress -eq $address -and $rows[0].LocalPort -eq $port -and $rows[0].OwningProcess -eq $PID) 'Listener address, port or owning process was decoded incorrectly'
    Assert (-not (Test-DreamSkinPortAvailable $port)) 'An occupied port was considered available'
    $expected=$address -in @('127.0.0.1','::1')
    Assert ((Test-DreamSkinCodexPortOwner $port $codex) -eq $expected) 'Loopback ownership check accepted a wildcard listener or rejected its correct owner'
    Assert (-not (Test-DreamSkinCodexPortOwner $port ([pscustomobject]@{Executable='C:\unrelated.exe'}))) 'Wrong executable was accepted'
  }finally{$listener.Stop()}
  Assert ((Get-DreamSkinPortListeners $port).Count -eq 0) 'Closed listener remained cached'
}
'PASS native IPv4/IPv6 discovery, ownership, wildcard rejection and fresh closed-port state'
