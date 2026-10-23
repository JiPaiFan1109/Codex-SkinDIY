$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../engine/scripts/common-windows.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('skin-intent-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null
try {
  $state=[pscustomobject]@{schemaVersion=1;port=9345;injectorPid=123;browserId='old-browser'}
  Write-DreamSkinRecoveryIntent -StateRoot $root -State $state
  $recovered=Read-DreamSkinRecoveryIntent -StateRoot $root
  if($recovered.browserId -ne 'old-browser'){throw 'Session loss discarded durable recovery intent'}
  Write-DreamSkinState -Path (Join-Path $root 'state.json') -State $state
  Remove-Item -LiteralPath (Join-Path $root 'state.json')
  if(-not (Read-DreamSkinRecoveryIntent $root)){throw 'Removing session must not disable recovery'}
  Clear-DreamSkinRecoveryIntent $root
  if(Read-DreamSkinRecoveryIntent $root){throw 'Explicit restore must disable recovery'}
  'PASS: durable intent survives session loss and explicit restore clears it'
} finally {
  $resolved=[IO.Path]::GetFullPath($root)
  if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup'}
  Remove-Item -LiteralPath $resolved -Recurse -Force
}
