$ErrorActionPreference='Stop'
$module=Join-Path $PSScriptRoot '../scripts/app-update.ps1'
$path=Join-Path ([IO.Path]::GetTempPath()) ('update-hash-'+[guid]::NewGuid().ToString('N'))
[IO.File]::WriteAllBytes($path,[Text.Encoding]::ASCII.GetBytes('abc'))
$worker=[PowerShell]::Create();$runspace=[RunspaceFactory]::CreateRunspace();$runspace.Open();$worker.Runspace=$runspace
try{
  $body={param($Module,$Path)
    $ErrorActionPreference='Stop';$PSModuleAutoLoadingPreference='None'
    function Get-FileHash {throw 'Get-FileHash unavailable in this worker'}
    . $Module
    $manifest=@{size=3;sha256='ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'}
    Assert-DynamicUpdateFile $Path $manifest
    $manifest.sha256='0'*64;$rejected=$false
    try{Assert-DynamicUpdateFile $Path $manifest}catch{$rejected=$true}
    if(-not $rejected){throw 'Corrupted update passed the native SHA-256 check'}
    return $true
  }
  $null=$worker.AddScript($body.ToString()).AddArgument($module).AddArgument($path)
  $result=$worker.Invoke()
  if($result[-1] -ne $true){throw 'Worker did not verify the payload'}
  'PASS real updater worker verifies SHA-256 without Get-FileHash or module autoloading; corrupt bytes rejected'
}finally{$worker.Dispose();$runspace.Dispose();Remove-Item -LiteralPath $path -Force}
