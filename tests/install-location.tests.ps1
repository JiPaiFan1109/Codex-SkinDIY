$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
$setup=[IO.File]::ReadAllText((Join-Path $repo 'installer/windows.iss'))
Assert ($setup -match '(?m)^DefaultDirName=\{localappdata\}\\CodexPage\s*$') 'Fresh setup must default to the CodexPage directory'
Assert ($setup -match 'AppId=\{\{97EC4AF8-3971-4B65-A78E-16B0D870C41D\}') 'Upgrade AppId must remain compatible'
Assert ($setup -match '(?m)^AppMutex=CodexDynamicSkinManager\s*$') 'Upgrade mutex must remain compatible'
Assert ($setup -match '(?m)^DisableDirPage=no\s*$') 'Interactive setup must show directory selection even on reinstall'
Assert ($setup -match '(?m)^UsePreviousAppDir=yes\s*$') 'Reinstall must default to the existing directory'
Assert ($setup -notmatch 'param:DIR|ExpectedDirectory') 'Setup still rejects custom directories'
# Evaluate only parameter defaults, never execute installation or runtime actions.
function Get-InstallRootDefault([string]$ScriptPath){
  $tokens=$null;$errors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile($ScriptPath,[ref]$tokens,[ref]$errors)
  Assert (-not $errors.Count) ('Script must parse: '+$ScriptPath)
  $parameter=$ast.ParamBlock.Parameters|Where-Object {$_.Name.VariablePath.UserPath -eq 'InstallRoot'}
  $scriptDirectory=Split-Path $ScriptPath -Parent
  $quotedDirectory="'"+($scriptDirectory -replace "'","''")+"'"
  $expression=$parameter.DefaultValue.Extent.Text -replace '\$PSScriptRoot',$quotedDirectory
  & ([scriptblock]::Create($expression))
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('codexpage-location-'+[guid]::NewGuid().ToString('N'))
$originalLocalAppData=$env:LOCALAPPDATA
try{
  New-Item -ItemType Directory -Path $temp|Out-Null
  $env:LOCALAPPDATA=$temp
  $installer=Join-Path $repo 'scripts/install.ps1'
  Assert ((Get-InstallRootDefault $installer) -eq (Join-Path $temp 'CodexPage')) 'Fresh script installation must use CodexPage'
  $legacy=Join-Path $temp 'CodexDynamicSkin'
  New-Item -ItemType Directory -Path (Join-Path $legacy 'scripts') -Force|Out-Null
  Set-Content -LiteralPath (Join-Path $legacy 'scripts/install.ps1') -Value '# existing installation'
  Assert ((Get-InstallRootDefault $installer) -eq $legacy) 'Script upgrade must retain an existing legacy installation'
  foreach($name in @('manage-background.ps1','check-upgrade.ps1')){
    foreach($directory in @('CodexPage','CodexDynamicSkin','custom installation')){
      $scriptDirectory=Join-Path (Join-Path $temp $directory) 'scripts'
      New-Item -ItemType Directory -Path $scriptDirectory -Force|Out-Null
      $scriptPath=Join-Path $scriptDirectory $name
      Copy-Item -LiteralPath (Join-Path $repo ('scripts/'+$name)) -Destination $scriptPath
      Assert ((Get-InstallRootDefault $scriptPath) -eq (Split-Path $scriptDirectory -Parent)) ('Runtime default must follow its installed directory: '+$name+' / '+$directory)
    }
  }
}finally{
  $env:LOCALAPPDATA=$originalLocalAppData
  if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}
}
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
