$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$script=Join-Path $repo 'scripts/get-release-assets.ps1'
$root=Join-Path ([IO.Path]::GetTempPath()) ('codexpage-assets-test-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null
function Reject([scriptblock]$action){$failed=$false;try{& $action|Out-Null}catch{$failed=$true};if(-not $failed){throw 'Incomplete or mismatched assets accepted'}}
try{
  foreach($name in @('CodexPage-Setup.exe','Codex-Skin-Manager-Setup.exe','CodexPage-2.1.1-windows-x64.zip','Codex-Dynamic-Skin-2.1.1-windows-x64.zip')){
    $path=Join-Path $root $name
    [IO.File]::WriteAllText($path,'same fixture bytes')
    [IO.File]::WriteAllText(($path+'.sha256'),(Get-FileHash $path).Hash.ToLowerInvariant()+'  '+$name)
  }
  foreach($name in @('update.json','update.sig')){[IO.File]::WriteAllText((Join-Path $root $name),'fixture')}
  $assets=@(& $script -OutputDirectory $root -Version '2.1.1')
  if($assets.Count -ne 10 -or $assets[0] -cne 'CodexPage-Setup.exe'){throw 'Canonical and compatibility assets must all be published, canonical first'}
  Remove-Item -LiteralPath (Join-Path $root 'CodexPage-Setup.exe')
  Reject {& $script -OutputDirectory $root -Version '2.1.1'}
  [IO.File]::WriteAllText((Join-Path $root 'CodexPage-Setup.exe'),'different bytes')
  Reject {& $script -OutputDirectory $root -Version '2.1.1'}
  [IO.File]::WriteAllText((Join-Path $root 'CodexPage-Setup.exe'),'same fixture bytes')
  [IO.File]::WriteAllText((Join-Path $root 'CodexPage-Setup.exe.sha256'),'invalid checksum')
  Reject {& $script -OutputDirectory $root -Version '2.1.1'}
  'PASS release inventory requires canonical names, compatibility copies and matching checksums'
}finally{
  if([IO.Path]::GetFullPath($root).StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $root -Recurse -Force}
}
