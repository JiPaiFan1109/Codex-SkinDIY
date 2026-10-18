param([string]$ScreenshotPath)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/skin-manager.ps1')
. (Join-Path $repo 'scripts/update-ui.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('update-ui-'+[guid]::NewGuid().ToString('N'))
New-Item $root -ItemType Directory|Out-Null
try{
  [IO.File]::WriteAllText((Join-Path $root 'VERSION'),'0.3.0')
  $window=New-DynamicSkinManagerWindow
  $script:SkinManager=@{Window=$window;Controls=@{};InstallRoot=$root;StateRoot=$root;ModuleRoot=(Join-Path $repo 'scripts');PrepareOnly=$true;Busy=$false}
  Initialize-DynamicUpdateUI
  $ui=$script:SkinManager
  if($ui.Controls.UpdateText.Text -ne '版本 0.3.0'){throw 'Installed version was not displayed'}
  foreach($name in @('CheckUpdateButton','InstallUpdateButton','SkipUpdateButton','LaterUpdateButton')){if(-not $ui.Controls[$name]){throw "Missing update action: $name"}}
  $ui.AvailableUpdate=[pscustomobject]@{version='0.4.0';notes='更新说明'}
  $ui.Controls.UpdateBanner.Visibility='Visible'
  $ui.Controls.SkipUpdateButton.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
  if((Read-DynamicUpdateState $root).SkippedVersion -ne '0.4.0' -or $ui.Controls.UpdateBanner.Visibility -ne 'Collapsed'){throw 'Skip button did not persist and dismiss the update'}
  $ui.Controls.UpdateBanner.Visibility='Visible'
  $ui.Controls.LaterUpdateButton.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
  if($ui.Controls.UpdateBanner.Visibility -ne 'Collapsed'){throw 'Later button did not dismiss the update'}
  $ui.AvailableUpdate=[pscustomobject]@{version='1.0.0';notes="1.皮肤管理中心界面升级`n2.能够自动批量引入本地Wallpaper Engine壁纸"}
  Show-DynamicUpdateNotice
  if($ui.Controls.UpdateText.Text -notmatch '1.0.0' -or $ui.Controls.UpdateText.Text -notmatch '0.3.0'){throw 'Update notice must show candidate and installed versions'}
  if($ui.Controls.UpdateNotes.Text -notmatch 'Wallpaper Engine'){throw 'Release highlights missing'}
  if($window.FindName('SettingsPanel').Visibility -ne 'Visible'){throw 'Automatic update is hidden behind settings'}

  $visual=$window.Content;$visual.Measure([Windows.Size]::new(1180,860));$visual.Arrange([Windows.Rect]::new(0,0,1180,860));$visual.UpdateLayout()
  if($ui.Controls.InstallUpdateButton.ActualWidth -le 0){throw 'Update action was not laid out'}
  if($ScreenshotPath){
    $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap(1180,860,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($visual);$encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap));$stream=[IO.File]::Create($ScreenshotPath)
    try{$encoder.Save($stream)}finally{$stream.Dispose()}
  }
  'PASS WPF update layout, version display, skip persistence and later action'
}finally{
  if($script:SkinManager){$script:SkinManager.UpdateTimer.Stop();$script:SkinManager.UpdateStartupTimer.Stop()}
  if($window){$window.Close()}
  Remove-Item -LiteralPath $root -Recurse -Force
}
