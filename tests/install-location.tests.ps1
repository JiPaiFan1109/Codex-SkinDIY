$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
$setup=[IO.File]::ReadAllText((Join-Path $repo 'installer/windows.iss'))
Assert ($setup -match '(?m)^DisableDirPage=no\s*$') 'Interactive setup must show directory selection even on reinstall'
Assert ($setup -match '(?m)^UsePreviousAppDir=yes\s*$') 'Reinstall must default to the existing directory'
Assert ($setup -notmatch 'param:DIR|ExpectedDirectory') 'Setup still rejects custom directories'
. (Join-Path $repo 'scripts/media.ps1')
Initialize-DynamicMedia -InstallRoot $repo
. (Join-Path $repo 'engine/scripts/video-windows.ps1')
Assert ((Get-DreamSkinThemePaths).Root -ieq $repo) 'Theme defaults must resolve beside the installed engine'
Assert ((Get-DreamSkinVideoPaths).Config -ieq (Join-Path $repo 'video-theme.json')) 'Video defaults must resolve beside the installed engine'
foreach($name in @('start-dream-skin.ps1','restore-dream-skin.ps1','common-windows.ps1','multi-instance.ps1')){
  $text=[IO.File]::ReadAllText((Join-Path $repo ('engine/scripts/'+$name)))
  Assert ($text -notmatch '\$env:LOCALAPPDATA') ('Engine still depends on the fixed installation path: '+$name)
}
'PASS directory selection, reinstall default and installation-relative theme/video state'
