$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/media.ps1');Initialize-DynamicMedia -InstallRoot $repo
. (Join-Path $repo 'scripts/wallpaper-library.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('skin-ux-'+[guid]::NewGuid().ToString('N'))
try{
  New-Item $root -ItemType Directory|Out-Null
  $script:restores=0
  $restored=Restore-DynamicWallpaperAppearance $root {$script:restores++;throw 'Fresh install must not restart ordinary Codex'}
  if($restored -ne $true -or $script:restores -ne 0){throw 'Original appearance must be a no-op'}
  $image=(Import-DynamicWallpaper (Join-Path $repo 'engine/assets/demo-background.png') Image $root).Item
  Use-DynamicWallpaper $root $image.Id {}|Out-Null
  $before=(Get-FileHash (Join-Path $root 'active-theme/theme.json')).Hash
  $script:attempts=0;$cancelled=$false
  try{Use-DynamicWallpaper $root $image.Id {$script:attempts++;throw [OperationCanceledException]::new('Cancelled by user')}|Out-Null}catch{$cancelled=$true}
  if(-not $cancelled -or $script:attempts -ne 1){throw 'Cancelled apply must restore files without a second restart attempt'}
  if((Get-FileHash (Join-Path $root 'active-theme/theme.json')).Hash -ne $before){throw 'Cancellation did not preserve original theme bytes'}
  Set-DreamSkinPaused -Paused $true -StateRoot $root|Out-Null
  $restored=Restore-DynamicWallpaperAppearance $root {$script:restores++;throw 'Already restored must not restart Codex again'}
  if($restored -ne $true -or $script:restores -ne 0){throw 'Repeat restore must be a no-op'}
  'PASS fresh restore, cancelled apply and repeat restore avoid unnecessary restart'
}finally{if(Test-Path $root){Remove-Item -LiteralPath $root -Recurse -Force}}
