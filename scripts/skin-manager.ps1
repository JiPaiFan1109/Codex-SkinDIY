function Get-DynamicVisibleWallpapers {
  param($Items,[ValidateSet('All','Image','Video')][string]$Filter)
  @($Items | Where-Object { $Filter -eq 'All' -or $_.Kind -eq $Filter })
}

function Get-DynamicCodexConnection {
  try {
    $codex=Get-DreamSkinCodexInstall
    [pscustomobject]@{Available=$true;Message=('已找到 Codex · '+$codex.Version);Executable=$codex.Executable;Error=$null}
  }catch{
    [pscustomobject]@{Available=$false;Message='未找到可用的 Codex，请先安装官方 Windows 版，再点击重新检测。';Executable=$null;Error=$_.Exception.Message}
  }
}

function Get-DynamicManagerActionState {
  param($Selected,$Status,[bool]$Busy,[bool]$PrepareOnly,[bool]$CodexAvailable=$true)
  $available=$null -ne $Selected -and $Selected.IsAvailable
  [pscustomobject]@{
    Import=(-not $Busy);Apply=($available -and -not $Busy -and -not $PrepareOnly -and $CodexAvailable)
    Rename=($available -and -not $Busy)
    Delete=($null -ne $Selected -and -not $Busy -and -not $Status.Error -and $Status.CurrentId -ne $Selected.Id)
    Open=(-not $Busy -and -not $PrepareOnly -and $CodexAvailable);Restore=(-not $Busy -and -not $PrepareOnly)
  }
}

function Get-DynamicManagerErrorMessage {
  param([System.Exception]$Exception)
  while($null -ne $Exception.InnerException){$Exception=$Exception.InnerException}
  $message=$Exception.Message
  $reasons=@{
    'cdp-launch-failed'='未能启动换肤版 Codex，请关闭 Codex 后从管理中心重试。'
    'cdp-direct-access-denied'='Windows 阻止了换肤启动，请重新打开官方 Codex，再从管理中心重试。'
    'cdp-endpoint-unavailable'='未能建立 Codex 换肤连接，请重新打开 Codex 后重试，或检查项目兼容性更新。'
    'port-unavailable'='换肤连接端口不可用，请稍后重试。'
    'state-reconciliation-failed'='无法安全确认此前的运行状态，请关闭 Codex 后重试。'
    'injector-start-failed'='换肤后台未能启动，请重试；仍失败时请查看安装目录中的日志。'
    'renderer-verification-failed'='未能确认壁纸已经生效，请重新打开 Codex 后重试。'
    'superseded'='本次操作已被较新的换肤操作取代。'
    'internal-start-failure'='换肤启动未完成，请查看安装目录中的日志后重试。'
  }
  foreach($category in $reasons.Keys){
    $message=$message.Replace(('应用失败：'+$category),$reasons[$category])
    $message=$message.Replace(('恢复未完成：'+$category),('恢复未完成：'+$reasons[$category]))
  }
  return $message
}

function New-DynamicSkinManagerWindow {
  param([string]$IconPath=(Join-Path (Split-Path $PSScriptRoot -Parent) 'appearance/skin-manager.ico'))
  Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
  if(-not ('DynamicSkin.WallpaperCard' -as [type])){
    # WPF cannot bind ImageSource from a PSObject-wrapped property reliably.
    Add-Type -ReferencedAssemblies @([Windows.Media.ImageSource].Assembly.Location,[Windows.DependencyObject].Assembly.Location) -TypeDefinition @'
namespace DynamicSkin {
  public sealed class WallpaperCard {
    public string Id { get; set; }
    public object Item { get; set; }
    public string Name { get; set; }
    public string Caption { get; set; }
    public string Placeholder { get; set; }
    public string CurrentVisibility { get; set; }
    public double CardWidth { get; set; }
    public double CardHeight { get; set; }
    public System.Windows.Media.ImageSource ThumbnailImage { get; set; }
  }
}
'@
  }
  $xaml=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'skin-manager.xaml'))
  $reader=New-Object Xml.XmlNodeReader ([xml]$xaml)
  try{$window=[Windows.Markup.XamlReader]::Load($reader)}finally{$reader.Close()}
  if(Test-Path -LiteralPath $IconPath -PathType Leaf){
    $iconStream=$null
    try{
      $iconStream=[IO.File]::OpenRead($IconPath)
      $image=[Windows.Media.Imaging.BitmapFrame]::Create($iconStream,[Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,[Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
      $image.Freeze();$window.Icon=$image
    }catch{
      # A missing or unreadable optional icon must not prevent managing wallpapers.
    }finally{if($iconStream){$iconStream.Dispose()}}
  }
  $appIcon=Join-Path $env:LOCALAPPDATA 'CodexDynamicSkin/icons/chatgpt-app-light.ico'
  if(Test-Path -LiteralPath $appIcon){
    $bitmap=Read-DynamicManagerBitmap $appIcon
    if($bitmap){$window.FindName('CodexIcon').Source=$bitmap;$window.FindName('CodexIconFallback').Visibility='Collapsed'}
  }
  $window.FindName('MinimizeButton').Add_Click({$script:SkinManager.Window.WindowState='Minimized'})
  $window.FindName('MaximizeButton').Add_Click({$w=$script:SkinManager.Window;if($w.WindowState -eq 'Maximized'){$w.WindowState='Normal'}else{$w.WindowState='Maximized'}})
  $window.FindName('CloseWindowButton').Add_Click({$script:SkinManager.Window.Close()})
  $window.FindName('TitleDragArea').Add_MouseLeftButtonDown({param($sender,$e);if($e.ClickCount -eq 2){$w=$script:SkinManager.Window;if($w.WindowState -eq 'Maximized'){$w.WindowState='Normal'}else{$w.WindowState='Maximized'}}else{$script:SkinManager.Window.DragMove()}})
  return $window
}

function Format-DynamicWallpaperSize {
  param([long]$Bytes)
  if($Bytes -ge 1GB){return ('{0:N1} GB' -f ($Bytes/1GB))}
  if($Bytes -ge 1MB){return ('{0:N1} MB' -f ($Bytes/1MB))}
  return ('{0:N0} KB' -f ([Math]::Max(1.0,$Bytes/1KB)))
}

function Read-DynamicManagerBitmap {
  param([string]$Path,[int]$DecodeWidth=640)
  if(-not $Path){return $null}
  try {
    Assert-DreamSkinNoReparseComponents -Path $Path
    if([IO.Path]::GetExtension($Path) -ieq '.ico'){
      $decoder=[Windows.Media.Imaging.BitmapDecoder]::Create([uri][IO.Path]::GetFullPath($Path),[Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,[Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
      $frame=$decoder.Frames|Sort-Object PixelWidth -Descending|Select-Object -First 1
      $frame.Freeze();return $frame
    }
    $bitmap=New-Object Windows.Media.Imaging.BitmapImage
    $bitmap.BeginInit();$bitmap.CacheOption=[Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bitmap.UriSource=[uri][IO.Path]::GetFullPath($Path);$bitmap.DecodePixelWidth=$DecodeWidth
    $bitmap.EndInit();$bitmap.Freeze()
    return $bitmap
  }catch{return $null}
}

function Stop-DynamicManagerPreview {
  $ui=$script:SkinManager
  $ui.Controls.PreviewVideo.Stop();$ui.Controls.PreviewVideo.Close();$ui.Controls.PreviewVideo.Source=$null
  $ui.Controls.PreviewVideo.Visibility='Collapsed'
  $ui.Controls.PlayButton.Content='播放预览';$ui.Playing=$false
}

function Update-DynamicManagerButtons {
  $ui=$script:SkinManager
  $state=Get-DynamicManagerActionState $ui.Selected $ui.Status $ui.Busy $ui.PrepareOnly ([bool]$ui.Connection.Available)
  foreach($action in @('Import','Apply','Rename','Delete','Open','Restore')){$ui.Controls[($action+'Button')].IsEnabled=$state.$action}
  $ui.Controls.SaveCurrentButton.IsEnabled=(-not $ui.Busy -and $ui.Status.HasExternalCurrent -and -not $ui.Status.Error)
  $ui.Controls.PlayButton.IsEnabled=(-not $ui.Busy)
  $ui.Controls.DetectButton.IsEnabled=(-not $ui.Busy)
  foreach($name in @('EngineImportButton','EngineFolderButton','PreviewApplyButton')){if($ui.Controls[$name]){$ui.Controls[$name].IsEnabled=(-not $ui.Busy)}}
  if($ui.Controls.PreviewApplyButton){$ui.Controls.PreviewApplyButton.IsEnabled=$state.Apply}
  if($ui.Controls.CheckUpdateButton){
    $ui.Controls.CheckUpdateButton.IsEnabled=(-not $ui.Busy -and -not $ui.UpdateWorker -and -not $ui.PrepareOnly)
    foreach($name in @('InstallUpdateButton','LaterUpdateButton','SkipUpdateButton')){$ui.Controls[$name].IsEnabled=(-not $ui.Busy -and -not $ui.UpdateWorker)}
  }
}

function Update-DynamicManagerSelection {
  $ui=$script:SkinManager
  Stop-DynamicManagerPreview
  $ui.Controls.PreviewImage.Source=$null;$ui.Controls.PreviewNotice.Text='';$ui.Controls.PlayButton.Visibility='Collapsed'
  $view=$ui.Controls.WallpaperList.SelectedItem
  $ui.Selected=$null
  if($view){$ui.Selected=$view.Item}
  $item=$ui.Selected
  if(-not $item){
    $ui.Controls.SelectedName.Text='尚未选择壁纸';$ui.Controls.SelectedName.ToolTip=$null
    $ui.Controls.SelectedDetails.Text='从下方选择壁纸，或导入新的图片与视频。';$ui.Controls.PreviewPlaceholder.Text='选择一张壁纸'
    $ui.Controls.SelectedStatus.Text='SELECTED WALLPAPER'
    foreach($field in @('SelectedFormat','SelectedSize','SelectedImportedAt')){$ui.Controls[$field].Text='—'}
  }else{
    $ui.Controls.SelectedName.Text=$item.Name;$ui.Controls.SelectedName.ToolTip=$item.Name
    $kind='静态图片';if($item.Kind -eq 'Video'){$kind='动态视频'}elseif($item.Kind -eq 'Unknown'){$kind='不可用'}
    $format='—';if($item.MediaPath){$format=[IO.Path]::GetExtension($item.MediaPath).TrimStart('.').ToUpperInvariant()}
    $ui.Controls.SelectedFormat.Text=$kind+' · '+$format
    $ui.Controls.SelectedSize.Text=Format-DynamicWallpaperSize $item.Size
    $ui.Controls.SelectedImportedAt.Text=$item.ImportedAtUtc.ToLocalTime().ToString('yyyy.MM.dd')
    $ui.Controls.SelectedStatus.Text='SELECTED WALLPAPER'
    $ui.Controls.SelectedDetails.Text='点击应用，让这张壁纸成为你的工作背景。'
    if($ui.Status.CurrentId -eq $item.Id){$ui.Controls.SelectedStatus.Text='CURRENT WALLPAPER';$ui.Controls.SelectedDetails.Text='当前正在使用这张壁纸。'}
    $ui.Controls.PreviewPlaceholder.Text='预览暂不可用'
    if(-not $item.IsAvailable){$ui.Controls.PreviewNotice.Text=$item.Error}
    elseif($item.Kind -eq 'Video'){
      $ui.Controls.PreviewImage.Source=Read-DynamicManagerBitmap $item.ThumbnailPath
      $ui.Controls.PlayButton.Visibility='Visible';$ui.Controls.PreviewNotice.Text='静音循环预览，播放不会改变当前背景。'
    }else{
      $bitmap=Read-DynamicManagerBitmap $item.MediaPath 1600
      if(-not $bitmap){$bitmap=Read-DynamicManagerBitmap $item.ThumbnailPath;$ui.Controls.PreviewNotice.Text='完整预览受限，已尝试显示缩略图。'}
      $ui.Controls.PreviewImage.Source=$bitmap
    }
  }
  Update-DynamicManagerButtons
}

function Update-DynamicManagerList {
  param([string]$SelectedId)
  $ui=$script:SkinManager
  if(-not $SelectedId -and $ui.Selected){$SelectedId=$ui.Selected.Id}
  $views=@(foreach($item in Get-DynamicVisibleWallpapers $ui.Items $ui.Filter){
    $kind='静态';$placeholder='图片';if($item.Kind -eq 'Video'){$kind='动态';$placeholder='视频'}
    if(-not $item.IsAvailable){$kind='不可用';$placeholder='!'}
    $visibility='Collapsed';if($ui.Status.CurrentId -eq $item.Id){$visibility='Visible'}
    $card=New-Object DynamicSkin.WallpaperCard
    $availableWidth=$ui.Controls.WallpaperList.ActualWidth
    if($availableWidth -lt 200){$availableWidth=$ui.Window.Width-238}
    $card.CardWidth=[Math]::Max(140,[Math]::Floor(($availableWidth-24)/4)-26)
    $card.CardHeight=[Math]::Round($card.CardWidth*0.625)
    $card.Id=$item.Id;$card.Item=$item;$card.Name=$item.Name;$card.Caption=($kind+' · '+(Format-DynamicWallpaperSize $item.Size))
    $card.Placeholder=$placeholder;$card.ThumbnailImage=Read-DynamicManagerBitmap $item.ThumbnailPath;$card.CurrentVisibility=$visibility
    $card
  })
  $ui.Controls.WallpaperList.ItemsSource=$views
  $selection=@($views|Where-Object Id -eq $SelectedId)
  if($selection.Count){$ui.Controls.WallpaperList.SelectedItem=$selection[0]}elseif($views.Count){$ui.Controls.WallpaperList.SelectedIndex=0}
  $ui.Controls.EmptyState.Visibility='Collapsed'
  if(-not $views.Count){$ui.Controls.EmptyState.Visibility='Visible';$ui.Controls.EmptyTitle.Text='你的壁纸收藏，从这里开始';if($ui.Items.Count){$ui.Controls.EmptyTitle.Text='此分类还没有壁纸'}}
  $total=0L;foreach($item in $ui.Items){$total+=$item.DiskSize}
  $ui.Controls.LibrarySummary.Text=('{0} 张壁纸 · {1}' -f $ui.Items.Count,(Format-DynamicWallpaperSize $total))
  foreach($name in @('All','Image','Video')){
    $ui.Controls[($name+'Filter')].BorderBrush=[Windows.Media.Brushes]::Transparent
    $ui.Controls[($name+'Filter')].Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#637B9E')
    $ui.Controls[($name+'Filter')].Background=[Windows.Media.Brushes]::Transparent
    if($ui.Filter -eq $name){
      $ui.Controls[($name+'Filter')].BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFromString('#EDEDF0')
      $ui.Controls[($name+'Filter')].Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#172134')
      $ui.Controls[($name+'Filter')].Background=[Windows.Media.Brushes]::White
    }
  }
  Update-DynamicManagerSelection
}

function Start-DynamicManagerWork {
  param([string]$Operation,[string]$Argument,[string]$Name)
  $ui=$script:SkinManager
  if($ui.Busy){return}
  Stop-DynamicManagerPreview
  $ui.Busy=$true;$ui.Controls.WorkProgress.Visibility='Visible';$ui.Controls.StatusText.Text='正在处理…'
  $ui.Controls.StatusText.Visibility='Visible'
  Update-DynamicManagerButtons
  $queue=New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
  $worker=[PowerShell]::Create()
  $runspace=[RunspaceFactory]::CreateRunspace();$runspace.ApartmentState='STA';$runspace.ThreadOptions='ReuseThread';$runspace.Open()
  $worker.Runspace=$runspace
  $body={
    param($InstallRoot,$StateRoot,$ModuleRoot,$Operation,$Argument,$Name,$PrepareOnly,$Queue)
    $ErrorActionPreference='Stop'
    . (Join-Path $ModuleRoot 'media.ps1');Initialize-DynamicMedia -InstallRoot $InstallRoot
    . (Join-Path $ModuleRoot 'wallpaper-library.ps1')
    . (Join-Path $ModuleRoot 'skin-manager.ps1')
    $report={param($message)$Queue.Enqueue([string]$message)}
    if($PrepareOnly -and $Operation -in @('Apply','Open','Restore')){throw '预览模式不能更改真实 Codex。'}
    $connection=[pscustomobject]@{Available=$false;Message='预览模式 · 不连接 Codex';Error=$null;Executable=$null}
    if(-not $PrepareOnly){$connection=Get-DynamicCodexConnection}
    if($Operation -in @('Apply','Open') -and -not $connection.Available){throw $connection.Message}
    $selected=$null;$message='壁纸库已加载。';$engineReport=$null
    try { switch($Operation){
      'Import' {
        $kind='Video';if([IO.Path]::GetExtension($Argument).ToLowerInvariant() -in @('.png','.jpg','.jpeg','.webp')){$kind='Image'}
        $result=Import-DynamicWallpaper $Argument $kind $StateRoot $report;$selected=$result.Item.Id
        $message='已保存到壁纸库，点击应用后生效。';if($result.AlreadyExists){$message='壁纸已存在，已选中原有项目。'}
      }
      'EngineImport' {
        $roots=@();if($Argument){$roots=@($Argument)}
        $batch=Import-DynamicWallpaperEngine -Roots $roots -StateRoot $StateRoot -Report $report
        $selected=$batch.SelectedId
        $message=('导入 {0}，已存在 {1}，不支持 {2}，失败 {3}。' -f $batch.Imported,$batch.Existing,$batch.Skipped,$batch.Failed)
        if(-not $batch.Roots.Count){$message='未找到本地 Wallpaper Engine 壁纸，请选择壁纸目录。'}
        $engineReport=$message+"`n"+($batch.Details -join "`n")
      }
      'Apply' {Use-DynamicWallpaper $StateRoot $Argument {Invoke-DynamicEngine -StateRoot $StateRoot}|Out-Null;$selected=$Argument;$message='壁纸已应用。'}
      'Rename' {Rename-DynamicWallpaper $StateRoot $Argument $Name|Out-Null;$selected=$Argument;$message='名称已保存。'}
      'Delete' {Remove-DynamicWallpaper $StateRoot $Argument;$message='壁纸已从库中删除。'}
      'SaveCurrent' {$result=Save-DynamicCurrentWallpaper $StateRoot $report;$selected=$result.Item.Id;Set-DynamicCurrentImportPromptDismissed $StateRoot;$message='当前背景已保存到壁纸库。'}
      'DismissPrompt' {Set-DynamicCurrentImportPromptDismissed $StateRoot}
      'Open' {Invoke-DynamicEngine -StateRoot $StateRoot;$message='Codex 已打开。'}
      'Restore' {
        $restored=Restore-DynamicWallpaperAppearance $StateRoot {Invoke-DynamicEngine -StateRoot $StateRoot -Restore}
        $message='当前为原始外观，壁纸收藏仍保留。'
        if($restored -eq $false){$message='已取消恢复。'}
      }
      'Refresh' { }
      default {throw '未知管理操作。'}
    }}catch{
      if(-not (Test-DynamicOperationCancelled $_.Exception)){throw}
      $selected=$Argument;$message='已取消操作，原有外观未改变。'
    }
    $status=Get-DynamicWallpaperStatus $StateRoot
    if($status.Error){$message='读取当前背景失败：'+$status.Error}
    elseif($Operation -eq 'Refresh' -and $status.HasExternalCurrent){$message='可点击“保存当前背景”，将当前画面加入收藏。'}
    if($PrepareOnly){$message='预览模式 · '+$message}
    [pscustomobject]@{Items=@(Get-DynamicWallpaperItems $StateRoot);Status=$status;Connection=$connection;SelectedId=$selected;Message=$message;EngineReport=$engineReport;PromptCurrent=($status.HasExternalCurrent -and -not (Test-DynamicCurrentImportPromptDismissed $StateRoot))}
  }
  $null=$worker.AddScript($body.ToString()).AddArgument($ui.InstallRoot).AddArgument($ui.StateRoot).AddArgument($ui.ModuleRoot).AddArgument($Operation).AddArgument($Argument).AddArgument($Name).AddArgument($ui.PrepareOnly).AddArgument($queue)
  $ui.Worker=$worker;$ui.Runspace=$runspace;$ui.Queue=$queue;$ui.Async=$worker.BeginInvoke();$ui.Timer.Start()
}

function Complete-DynamicManagerWork {
  $ui=$script:SkinManager
  $message=$null
  while($ui.Queue.TryDequeue([ref]$message)){$ui.Controls.StatusText.Text=$message}
  if(-not $ui.Async.IsCompleted){return}
  $ui.Timer.Stop();$prompt=$false
  try {
    $results=$ui.Worker.EndInvoke($ui.Async)
    if($ui.Worker.HadErrors){throw $ui.Worker.Streams.Error[0].Exception}
    $result=$results|Select-Object -Last 1
    if(-not $result){throw '后台操作未返回结果。'}
    $ui.Items=@($result.Items);$ui.Status=$result.Status;$ui.Controls.StatusText.Text=$result.Message
    if($null -ne $result.EngineReport){$ui.Controls.EngineReport.Text=$result.EngineReport}
    $ui.Connection=$result.Connection;$ui.Controls.ConnectionText.Text=$result.Connection.Message
    $ui.Window.FindName('ConnectionBadge').Visibility='Collapsed'
    if($result.Connection.Available){$ui.Window.FindName('ConnectionBadge').Visibility='Visible'}
    $ui.Controls.ConnectionText.ToolTip=$result.Connection.Executable
    if($result.Connection.Error){$ui.Controls.ConnectionText.ToolTip=$result.Connection.Error}
    if($result.SelectedId -and $ui.Filter -ne 'All'){
      $selected=@($ui.Items|Where-Object Id -eq $result.SelectedId)
      if($selected.Count -and $selected[0].Kind -ne $ui.Filter){$ui.Filter=$selected[0].Kind}
    }
    if(-not $result.SelectedId -and $ui.Filter -eq 'Video' -and $ui.Items.Count -and @($ui.Items|Where-Object Kind -eq 'Video').Count -eq 0){$ui.Filter='Image'}
    Update-DynamicManagerList $result.SelectedId
    $prompt=$result.PromptCurrent -and -not $ui.PromptShown
  }catch{
    $errorMessage=Get-DynamicManagerErrorMessage $_.Exception
    $ui.Controls.StatusText.Text='操作未完成：'+$errorMessage
    [Windows.MessageBox]::Show($ui.Window,$errorMessage,'操作未完成','OK','Warning')|Out-Null
  }finally{
    $ui.Worker.Dispose();$ui.Runspace.Dispose();$ui.Worker=$null;$ui.Runspace=$null;$ui.Async=$null
    $ui.Busy=$false;$ui.Controls.WorkProgress.Visibility='Collapsed';Update-DynamicManagerButtons
  }
  if($prompt){
    $ui.PromptShown=$true
    $choice=[Windows.MessageBox]::Show($ui.Window,'是否将当前使用的背景保存到壁纸库？选择“否”后仍可随时手动保存。','保存当前背景','YesNo','Question')
    if($choice -eq 'Yes'){Start-DynamicManagerWork SaveCurrent}else{Start-DynamicManagerWork DismissPrompt}
  }
}

function Show-DynamicWallpaperRename {
  $ui=$script:SkinManager
  $dialog=New-Object Windows.Window
  $dialog.Title='重命名壁纸';$dialog.Owner=$ui.Window;$dialog.Width=400;$dialog.Height=180;$dialog.ResizeMode='NoResize';$dialog.WindowStartupLocation='CenterOwner'
  $panel=New-Object Windows.Controls.StackPanel;$panel.Margin='20'
  $input=New-Object Windows.Controls.TextBox;$input.Text=$ui.Selected.Name;$input.Margin='0,0,0,16';$input.Padding='8';$input.MaxLength=240
  $save=New-Object Windows.Controls.Button;$save.Content='保存';$save.Padding='12,8';$save.IsDefault=$true
  $save.Add_Click({$dialog.DialogResult=$true}.GetNewClosure())
  $panel.Children.Add($input)|Out-Null;$panel.Children.Add($save)|Out-Null;$dialog.Content=$panel
  $input.SelectAll();$input.Focus()|Out-Null
  if($dialog.ShowDialog()){Start-DynamicManagerWork Rename $ui.Selected.Id $input.Text}
}

function Show-DynamicSkinManager {
  param([string]$InstallRoot,[string]$StateRoot,[switch]$PrepareOnly)
  if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw '管理中心需要在 STA 模式下运行，请使用 powershell.exe -STA 启动。'}
  $window=New-DynamicSkinManagerWindow
  $controls=@{}
  foreach($name in @('ImportButton','AllFilter','ImageFilter','VideoFilter','WallpaperList','LibrarySummary','EmptyState','EmptyTitle','PreviewPlaceholder','PreviewImage','PreviewVideo','PlayButton','SelectedName','SelectedDetails','SelectedFormat','SelectedSize','SelectedImportedAt','SelectedStatus','PreviewNotice','ApplyButton','RenameButton','DeleteButton','SaveCurrentButton','WorkProgress','StatusText','OpenButton','RestoreButton','ConnectionText','DetectButton')){$controls[$name]=$window.FindName($name)}
  foreach($name in @('LocalNavButton','EngineNavButton','EngineImportButton','EngineFolderButton','EnginePanel','EngineReport','SettingsButton','SettingsPanel','PreviewOverlay','ClosePreviewButton','PreviewApplyButton')){$controls[$name]=$window.FindName($name)}
  $script:SkinManager=@{Window=$window;Controls=$controls;InstallRoot=$InstallRoot;StateRoot=$StateRoot;ModuleRoot=$PSScriptRoot;PrepareOnly=[bool]$PrepareOnly;Items=@();Status=[pscustomobject]@{CurrentId=$null;Paused=$false;HasExternalCurrent=$false;Error=$null};Selected=$null;Filter='Video';Busy=$false;Playing=$false;PromptShown=$false;Worker=$null;Runspace=$null;Async=$null}
  $timer=New-Object Windows.Threading.DispatcherTimer;$timer.Interval=[timespan]::FromMilliseconds(120);$timer.Add_Tick({Complete-DynamicManagerWork});$script:SkinManager.Timer=$timer
  $script:SkinManager.Connection=[pscustomobject]@{Available=$false}
  . (Join-Path $PSScriptRoot 'update-ui.ps1')
  Initialize-DynamicUpdateUI
  $controls.LocalNavButton.Add_Click({$script:SkinManager.Controls.EnginePanel.Visibility='Collapsed'})
  $controls.EngineNavButton.Add_Click({$script:SkinManager.Controls.EnginePanel.Visibility='Visible'})
  $controls.SettingsButton.Add_Click({$panel=$script:SkinManager.Controls.SettingsPanel;if($panel.Visibility -eq 'Visible'){$panel.Visibility='Collapsed'}else{$panel.Visibility='Visible'}})
  $controls.EngineImportButton.Add_Click({
    $ui=$script:SkinManager
    if([Windows.MessageBox]::Show($ui.Window,'查找本机 Steam 库中的 Wallpaper Engine 壁纸并批量导入？原文件会保留。','导入本地壁纸','YesNo','Question') -eq 'Yes'){Start-DynamicManagerWork EngineImport}
  })
  $controls.EngineFolderButton.Add_Click({
    Add-Type -AssemblyName System.Windows.Forms
    $dialog=New-Object Windows.Forms.FolderBrowserDialog
    $dialog.Description='选择包含 Wallpaper Engine 项目子文件夹的目录（如 431960 或 myprojects）'
    try{if($dialog.ShowDialog() -eq 'OK'){Start-DynamicManagerWork EngineImport $dialog.SelectedPath}}finally{$dialog.Dispose()}
  })
  $controls.ClosePreviewButton.Add_Click({Close-DynamicCodexPreview})
  $controls.PreviewApplyButton.Add_Click({Start-DynamicManagerWork Apply $script:SkinManager.Selected.Id})
  $controls.WallpaperList.Add_PreviewMouseLeftButtonUp({
    param($sender,$eventArgs)
    $element=$eventArgs.OriginalSource
    while($element -and $element -isnot [Windows.Controls.ListBoxItem]){try{$element=[Windows.Media.VisualTreeHelper]::GetParent($element)}catch{$element=$null}}
    if($element){$script:SkinManager.Controls.WallpaperList.SelectedItem=$element.Content;Show-DynamicCodexPreview}
  })
  $controls.WallpaperList.Add_KeyDown({param($sender,$eventArgs);if($eventArgs.Key -eq 'Return'){Show-DynamicCodexPreview}})
  $window.Add_KeyDown({param($sender,$eventArgs);if($eventArgs.Key -eq 'Escape'){Close-DynamicCodexPreview;$script:SkinManager.Controls.SettingsPanel.Visibility='Collapsed'}})
  $window.Add_SizeChanged({if($script:SkinManager -and -not $script:SkinManager.Busy){Update-DynamicManagerList}})
  $controls.DetectButton.Add_Click({Start-DynamicManagerWork Refresh})
  $controls.WallpaperList.Add_SelectionChanged({Update-DynamicManagerSelection})
  $controls.AllFilter.Add_Click({$script:SkinManager.Filter='All';Update-DynamicManagerList})
  $controls.ImageFilter.Add_Click({$script:SkinManager.Filter='Image';Update-DynamicManagerList})
  $controls.VideoFilter.Add_Click({$script:SkinManager.Filter='Video';Update-DynamicManagerList})
  $controls.ImportButton.Add_Click({
    $dialog=New-Object Microsoft.Win32.OpenFileDialog
    $dialog.Title='导入壁纸';$dialog.Filter='图片和视频|*.png;*.jpg;*.jpeg;*.webp;*.mp4;*.mov;*.m4v;*.wmv;*.avi;*.mkv;*.webm|静态图片|*.png;*.jpg;*.jpeg;*.webp|动态视频|*.mp4;*.mov;*.m4v;*.wmv;*.avi;*.mkv;*.webm'
    if($dialog.ShowDialog($script:SkinManager.Window)){Start-DynamicManagerWork Import $dialog.FileName}
  })
  $controls.ApplyButton.Add_Click({Start-DynamicManagerWork Apply $script:SkinManager.Selected.Id})
  $controls.RenameButton.Add_Click({Show-DynamicWallpaperRename})
  $controls.DeleteButton.Add_Click({
    $ui=$script:SkinManager
    if([Windows.MessageBox]::Show($ui.Window,('删除“'+$ui.Selected.Name+'”？只会删除库中的副本，不会删除导入的原文件。'),'删除壁纸','YesNo','Warning') -eq 'Yes'){
      Stop-DynamicManagerPreview;Start-DynamicManagerWork Delete $ui.Selected.Id
    }
  })
  $controls.SaveCurrentButton.Add_Click({Start-DynamicManagerWork SaveCurrent})
  $controls.OpenButton.Add_Click({Start-DynamicManagerWork Open})
  $controls.RestoreButton.Add_Click({Start-DynamicManagerWork Restore})
  $controls.PlayButton.Add_Click({
    $ui=$script:SkinManager
    if($ui.Playing){$ui.Controls.PreviewVideo.Pause();$ui.Playing=$false;$ui.Controls.PlayButton.Content='继续播放'}
    elseif($ui.Selected -and $ui.Selected.IsAvailable){
      if(-not $ui.Controls.PreviewVideo.Source){$ui.Controls.PreviewVideo.Source=[uri]$ui.Selected.MediaPath}
      $ui.Controls.PreviewVideo.Visibility='Visible';$ui.Controls.PreviewVideo.Play();$ui.Playing=$true;$ui.Controls.PlayButton.Content='暂停预览'
    }
  })
  $controls.PreviewVideo.Add_MediaEnded({$video=$script:SkinManager.Controls.PreviewVideo;$video.Position=[timespan]::Zero;$video.Play()})
  $controls.PreviewVideo.Add_MediaFailed({Stop-DynamicManagerPreview;$script:SkinManager.Controls.PreviewNotice.Text='本机无法播放此预览。文件仍保留，可尝试应用壁纸。'})
  $window.Add_Closing({param($sender,$eventArgs);if($script:SkinManager.Busy){$eventArgs.Cancel=$true;$script:SkinManager.Controls.StatusText.Text='任务仍在进行，请等待完成后再关闭窗口。'}})
  $window.Add_ContentRendered({if(-not $script:SkinManager.Async){Start-DynamicManagerWork Refresh}})
  try {Update-DynamicManagerButtons;$null=$window.ShowDialog()}
  finally {
    Stop-DynamicManagerPreview;$timer.Stop()
    $script:SkinManager.UpdateTimer.Stop();$script:SkinManager.UpdateStartupTimer.Stop()
    if($script:SkinManager.UpdateWorker){$script:SkinManager.UpdateWorker.Stop();$script:SkinManager.UpdateWorker.Dispose()}
    if($script:SkinManager.UpdateRunspace){$script:SkinManager.UpdateRunspace.Dispose()}
    if($script:SkinManager.Worker){$script:SkinManager.Worker.Dispose()};if($script:SkinManager.Runspace){$script:SkinManager.Runspace.Dispose()};$script:SkinManager=$null
  }
}

function Show-DynamicCodexPreview {
  $ui=$script:SkinManager
  if($ui.Busy -or -not $ui.Selected){return}
  Update-DynamicManagerSelection
  $ui.Controls.PreviewOverlay.Visibility='Visible'
  if($ui.Selected.Kind -eq 'Video' -and $ui.Selected.IsAvailable){
    $ui.Controls.PreviewVideo.Source=[uri]$ui.Selected.MediaPath
    $ui.Controls.PreviewVideo.Visibility='Visible';$ui.Controls.PreviewVideo.Play();$ui.Playing=$true;$ui.Controls.PlayButton.Content='暂停预览'
  }
}
function Close-DynamicCodexPreview {
  Stop-DynamicManagerPreview
  $script:SkinManager.Controls.PreviewOverlay.Visibility='Collapsed'
}
