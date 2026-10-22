$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/skin-manager.ps1')
function Assert($Value,$Message){if(-not $Value){throw $Message}}

$window=$null
try{
  $window=New-DynamicSkinManagerWindow
  $window.ShowActivated=$false;$window.ShowInTaskbar=$false
  $window.WindowStartupLocation='Manual';$window.Left=-10000;$window.Top=-10000
  $script:SkinManager=@{Busy=$true;UpdateClosing=$false;Controls=@{StatusText=$window.FindName('StatusText')}}
  Register-DynamicManagerClosingGuard $window
  $window.Show()
  $window.Close()
  $window.Dispatcher.Invoke([action]{})
  Assert $window.IsVisible 'A normal close must remain blocked while a task is busy'
  Assert (-not [string]::IsNullOrWhiteSpace([string]$script:SkinManager.Controls.StatusText.Text)) 'Blocked close must explain why the window stayed open'

  $script:SkinManager.UpdateClosing=$true
  $window.Close()
  $window.Dispatcher.Invoke([action]{})
  Assert (-not $window.IsVisible) 'The upgrade-owned close must bypass the busy guard'
  'PASS busy close guard and upgrade close bypass'
}finally{
  if($script:SkinManager){$script:SkinManager.Busy=$false}
  if($window -and $window.IsVisible){$window.Close()}
  $script:SkinManager=$null
}
