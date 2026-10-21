param([string]$CaptureDirectory)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../engine/scripts/common-windows.ps1')
. (Join-Path $PSScriptRoot '../scripts/skin-manager.ps1')
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
$window=New-DynamicSkinManagerWindow
try{
  $controls=@{}
  foreach($match in [regex]::Matches([IO.File]::ReadAllText((Join-Path $PSScriptRoot '../scripts/skin-manager.xaml')),'x:Name="([^"]+)"')){$controls[$match.Groups[1].Value]=$window.FindName($match.Groups[1].Value)}
  $script:SkinManager=@{Window=$window;Controls=$controls;Busy=$false;PrepareOnly=$false;Connection=[pscustomobject]@{Available=$true;Connected=$false;Version='26.1013.4894.0';Message='已安装 Codex 26.1013.4894.0，尚未建立壁纸连接。'}}
  Update-DynamicManagerConnectionBadge
  Assert ($controls.ConnectionLabel.Text -eq '已找到Codex') 'Known Store install is still labelled missing'
  Show-DynamicManagerConfirmation -Title 'Codex 连接未完成' -Message '未能建立 Codex 换肤连接，请保存工作并关闭 Codex，再点击图标重试。仍失败时，请提供日志供排查。' -Action {} -AcceptText '知道了' -NoticeOnly
  Assert ($controls.ConfirmCancelButton.Visibility -eq 'Collapsed') 'Failure details need acknowledgement, not an unused cancel action'
  Complete-DynamicManagerConfirmation $true
  if($CaptureDirectory){[void][IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($CaptureDirectory))}
  foreach($size in @(@(1440,840),@(900,525))){
    foreach($state in @('missing','locate','disconnected','loading','failure','connected')){
      $controls.ConfirmationOverlay.Visibility='Collapsed'
      $script:SkinManager.Connection.Available=$state -notin @('missing','locate')
      $script:SkinManager.Connection.Connected=$state -eq 'connected'
      Set-DynamicConnectionChecking $false
      if($state -eq 'locate'){Show-DynamicCodexLocateDialog}
      if($state -eq 'loading'){$script:SkinManager.PendingOperation='Open';Set-DynamicConnectionChecking $true}
      if($state -eq 'failure'){Show-DynamicManagerConfirmation -Title 'Codex 连接未完成' -Message '未能建立 Codex 换肤连接，请保存工作并关闭 Codex，再点击图标重试。仍失败时，请提供日志供排查。' -Action {} -AcceptText '知道了' -NoticeOnly}
      $surface=$window.Content
      $surface.Measure([Windows.Size]::new($size[0],$size[1]));$surface.Arrange([Windows.Rect]::new(0,0,$size[0],$size[1]));$surface.UpdateLayout()
      foreach($name in @('ConnectionLabel','ConnectionDetail','OpenButton')){
        $control=$controls[$name]
        $bounds=$control.TransformToAncestor($surface).TransformBounds([Windows.Rect]::new(0,0,$control.ActualWidth,$control.ActualHeight))
        Assert ($bounds.Left -ge 0 -and $bounds.Right -le $size[0] -and $bounds.Bottom -le $size[1]) "$name clips at $($size[0])"
        if($control -is [Windows.Controls.TextBlock]){
          $text=[Windows.Media.FormattedText]::new($control.Text,[Globalization.CultureInfo]::CurrentCulture,[Windows.FlowDirection]::LeftToRight,[Windows.Media.Typeface]::new($control.FontFamily,$control.FontStyle,$control.FontWeight,$control.FontStretch),$control.FontSize,$control.Foreground)
          Assert ($text.Width -le $control.ActualWidth+1) "$name text is clipped"
        }
      }
      if($CaptureDirectory){
        $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new($size[0],$size[1],96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($surface)
        $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $stream=[IO.File]::Create((Join-Path $CaptureDirectory ("connection-$state-$($size[0]).png")));try{$encoder.Save($stream)}finally{$stream.Dispose()}
      }
    }
  }
  Set-DynamicConnectionChecking $false
  Show-DynamicManagerConfirmation 'Confirm' 'Original confirmation' {} -AcceptText '确认'
  Assert ($controls.ConfirmCancelButton.Visibility -eq 'Visible') 'Notice changed subsequent confirmation buttons'
  'PASS disconnected/loading/failure/connected render bounds at 1440x840 and 900x525; no visible window created'
}finally{$window.Close();$script:SkinManager=$null}
