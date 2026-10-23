param([Parameter(Mandatory)][string]$LegacyPackage,[Parameter(Mandatory)][string]$ReleaseDirectory)
$ErrorActionPreference='Stop'
$LegacyPackage=(Resolve-Path $LegacyPackage).Path
$ReleaseDirectory=(Resolve-Path $ReleaseDirectory).Path
. (Join-Path $LegacyPackage 'scripts/skin-manager.ps1')
. (Join-Path $LegacyPackage 'scripts/update-ui.ps1')
$manifest=Read-DynamicSignedUpdate (Join-Path $ReleaseDirectory 'update.json') (Join-Path $ReleaseDirectory 'update.sig') (Join-Path $LegacyPackage 'scripts/update-public-key.xml') (([IO.File]::ReadAllText((Join-Path $ReleaseDirectory 'update.json'))|ConvertFrom-Json).version)
Assert-DynamicUpdateFile (Join-Path $ReleaseDirectory 'Codex-Skin-Manager-Setup.exe') $manifest
$window=New-DynamicSkinManagerWindow
try{
  $script:SkinManager=@{Window=$window;AvailableUpdate=$manifest;AppVersion=[IO.File]::ReadAllText((Join-Path $LegacyPackage 'VERSION')).Trim();Controls=@{}}
  foreach($name in @('UpdateText','UpdateNotes','UpdateBanner')){$script:SkinManager.Controls[$name]=$window.FindName($name)}
  Show-DynamicUpdateNotice
  if($script:SkinManager.Controls.UpdateNotes.Text -cne $manifest.notes){throw 'Legacy notification did not display the signed release notes'}
  if($window.FindName('SettingsPanel').Visibility -ne 'Visible' -or $script:SkinManager.Controls.UpdateBanner.Visibility -ne 'Visible'){throw 'Legacy notification is hidden'}
  'PASS legacy signature verification and signed release notification'
}finally{$window.Close();$script:SkinManager=$null}
