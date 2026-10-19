function Get-DynamicVisibleWallpapers {
  param($Items,[ValidateSet('All','Image','Video')][string]$Filter,[ValidateSet('All','Local','WallpaperEngine')][string]$Source='All')
  @($Items | Where-Object {
    $sources=@($_.Sources);if(-not $_.Sources){$sources=@('Local')}
    ($Filter -eq 'All' -or $_.Kind -eq $Filter) -and ($Source -eq 'All' -or $sources -contains $Source)
  })
}

function Get-DynamicCodexConnection {
  param([string]$StateRoot=(Join-Path $env:LOCALAPPDATA 'CodexDynamicSkin'))
  try {
    $codex=Get-DreamSkinCodexInstall
    $connected=$false;$version=$codex.Version
    if(Get-Command Read-DreamSkinState -ErrorAction SilentlyContinue){
      try{
        $state=Read-DreamSkinState -Path (Join-Path $StateRoot 'state.json')
        if($state -and $state.port){
          $verified=Get-DreamSkinVerifiedCdpIdentityForAnyRegistered -Port $state.port
          if($verified -and $verified.Identity.BrowserId -eq $state.browserId){$connected=$true;$version=$verified.Codex.Version}
        }
      }catch{}
    }
    $message='连接失败 · 已安装 Codex '+$version+'，尚未建立换肤连接。'
    if($connected){$message='连接成功 · Codex '+$version}
    [pscustomobject]@{Available=$true;Connected=$connected;Version=$version;Message=$message;Executable=$codex.Executable;Error=$null}
  }catch{
    [pscustomobject]@{Available=$false;Connected=$false;Version=$null;Message='连接失败 · 未找到可用的 Codex，请先安装官方 Windows 版，再点击重新检测。';Executable=$null;Error=$_.Exception.Message}
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
  $window.FindName('MaximizeButton').Add_Click({Switch-DynamicManagerZoom $script:SkinManager.Window})
  $window.FindName('CloseWindowButton').Add_Click({$script:SkinManager.Window.Close()})
  foreach($asset in @(@('EngineNavImage','wallpaper-engine.png'),@('ApplyIcon','apply-wallpaper.png'))){
    $path=Join-Path (Split-Path $PSScriptRoot -Parent) ('appearance/'+$asset[1])
    $frame=[Windows.Media.Imaging.BitmapFrame]::Create([uri]$path,[Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,[Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
    $frame.Freeze();$window.FindName($asset[0]).Source=$frame
  }
  foreach($corner in @('TopLeft','TopRight','BottomLeft','BottomRight')){
    $thumb=$window.FindName('Resize'+$corner);$thumb.Tag=$corner
    $thumb.Add_DragDelta({param($sender,$e)
      $w=[Windows.Window]::GetWindow($sender)
      $bounds=Get-DynamicProportionalBounds $w.Left $w.Top $w.Width $w.Height ([string]$sender.Tag) $e.HorizontalChange $e.VerticalChange
      $w.Left=$bounds.Left;$w.Top=$bounds.Top;$w.Width=$bounds.Width;$w.Height=$bounds.Height
      $w.Tag=$null;$e.Handled=$true
    })
  }
  $area=[Windows.SystemParameters]::WorkArea
  $window.Width=[Math]::Max(900,[Math]::Min(1440,[Math]::Min($area.Width*0.85,$area.Height*0.85*12/7)))
  $window.Height=$window.Width*7/12
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
    $cache=$null;$key=$null
    if($script:SkinManager){
      if(-not $script:SkinManager.BitmapCache){$script:SkinManager.BitmapCache=@{}}
      $cache=$script:SkinManager.BitmapCache
      $file=Get-Item -LiteralPath $Path -ErrorAction Stop
      $key=$file.FullName+'|'+$file.Length+'|'+$file.LastWriteTimeUtc.Ticks+'|'+$DecodeWidth
      if($cache.ContainsKey($key)){return $cache[$key]}
    }
    if([IO.Path]::GetExtension($Path) -ieq '.ico'){
      $decoder=[Windows.Media.Imaging.BitmapDecoder]::Create([uri][IO.Path]::GetFullPath($Path),[Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,[Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
      $frame=$decoder.Frames|Sort-Object PixelWidth -Descending|Select-Object -First 1
      $frame.Freeze();return $frame
    }
    $bitmap=New-Object Windows.Media.Imaging.BitmapImage
    $bitmap.BeginInit();$bitmap.CacheOption=[Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bitmap.UriSource=[uri][IO.Path]::GetFullPath($Path);$bitmap.DecodePixelWidth=$DecodeWidth
    $bitmap.EndInit();$bitmap.Freeze()
    if($cache -ne $null){if($cache.Count -ge 64){$cache.Clear()};$cache[$key]=$bitmap}
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
  $ui.Controls.PlayButton.IsEnabled=(-not $ui.Busy)
  $ui.Controls.OpenButton.IsEnabled=$true
  foreach($name in @('LocalNavButton','EngineNavButton','ImageFilter','VideoFilter')){if($ui.Controls[$name]){$ui.Controls[$name].IsEnabled=(-not $ui.Busy)}}
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
      $path=$item.MediaPath;$width=1600
      if($ui.Controls.PreviewOverlay.Visibility -ne 'Visible' -and $item.ThumbnailPath){$path=$item.ThumbnailPath;$width=640}
      $bitmap=Read-DynamicManagerBitmap $path $width
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
  $source='Local';if($ui.Source){$source=$ui.Source}
  $views=@(foreach($item in Get-DynamicVisibleWallpapers $ui.Items $ui.Filter $source){
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
  foreach($name in @('All','Image','Video')){
    if(-not $ui.Controls[($name+'Filter')]){continue}
    $ui.Controls[($name+'Filter')].BorderBrush=[Windows.Media.Brushes]::Transparent
    $ui.Controls[($name+'Filter')].Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#637B9E')
    $ui.Controls[($name+'Filter')].Background=[Windows.Media.Brushes]::Transparent
    if($ui.Filter -eq $name){
      $ui.Controls[($name+'Filter')].BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFromString('#EDEDF0')
      $ui.Controls[($name+'Filter')].Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#172134')
    }
  }
  Update-DynamicManagerNavigation
  Update-DynamicManagerFilterSlider
  Update-DynamicManagerSelection
}

function Start-DynamicManagerWork {
  param([string]$Operation,[string]$Argument,[string]$Name)
  $ui=$script:SkinManager
  if($ui.Busy){return}
  Stop-DynamicManagerPreview
  $ui.Busy=$true;$ui.Controls.WorkProgress.Visibility='Visible';$ui.Controls.StatusText.Text='正在处理…'
  $ui.Controls.StatusText.Visibility='Visible'
  if($Operation -eq 'Refresh'){Set-DynamicConnectionChecking $true}
  $ui.PendingOperation=$Operation
  Update-DynamicManagerButtons
  $queue=New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
  $worker=[PowerShell]::Create()
  $runspace=[RunspaceFactory]::CreateRunspace();$runspace.ApartmentState='STA';$runspace.ThreadOptions='ReuseThread';$runspace.Open()
  $worker.Runspace=$runspace
  $body={
    param($InstallRoot,$StateRoot,$ModuleRoot,$Operation,$Argument,$Name,$PrepareOnly,$Queue,$PreviousConnection)
    $ErrorActionPreference='Stop'
    . (Join-Path $ModuleRoot 'media.ps1');Initialize-DynamicMedia -InstallRoot $InstallRoot
    . (Join-Path $ModuleRoot 'wallpaper-library.ps1')
    . (Join-Path $ModuleRoot 'skin-manager.ps1')
    $report={param($message)$Queue.Enqueue([string]$message)}
    if($PrepareOnly -and $Operation -in @('Apply','Open','Restore')){throw '预览模式不能更改真实 Codex。'}
    # Detection is read-only, including in preview mode. Apply/open/restore remain blocked there.
    $connection=$PreviousConnection
    if(-not $connection -or $Operation -in @('Refresh','Apply','Open','Restore')){$connection=Get-DynamicCodexConnection}
    if($Operation -in @('Apply','Open') -and -not $connection.Available){throw $connection.Message}
    $selected=$null;$message='壁纸库已加载。';$engineReport=$null;$cancelled=$false
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
      'Swap' {Switch-DynamicWallpaperOrder $StateRoot $Argument $Name;$selected=$Argument;$message='壁纸位置已交换。'}
      'Apply' {Use-DynamicWallpaper $StateRoot $Argument {Invoke-DynamicEngine -StateRoot $StateRoot}|Out-Null;$selected=$Argument;$message='壁纸已应用。'}
      'Rename' {Rename-DynamicWallpaper $StateRoot $Argument $Name|Out-Null;$selected=$Argument;$message='名称已保存。'}
      'Delete' {Remove-DynamicWallpaper $StateRoot $Argument;$message='壁纸已从库中删除。'}
      'SaveCurrent' {$result=Save-DynamicCurrentWallpaper $StateRoot $report;$selected=$result.Item.Id;Set-DynamicCurrentImportPromptDismissed $StateRoot;$message='当前背景已保存到壁纸库。'}
      'DismissPrompt' {Set-DynamicCurrentImportPromptDismissed $StateRoot}
      'Open' {Invoke-DynamicEngine -StateRoot $StateRoot;$message='Codex 已打开。'}
      'Restore' {
        $restored=Restore-DynamicWallpaperAppearance $StateRoot {Invoke-DynamicEngine -StateRoot $StateRoot -Restore}
        $message='当前为原始外观，壁纸收藏仍保留。'
        if($restored -eq $false){$message='已取消恢复。';$cancelled=$true}
      }
      'Refresh' { }
      default {throw '未知管理操作。'}
    }}catch{
      if(-not (Test-DynamicOperationCancelled $_.Exception)){throw}
      $selected=$Argument;$message='已取消操作，原有外观未改变。';$cancelled=$true
    }
    $status=Get-DynamicWallpaperStatus $StateRoot
    if($Operation -in @('Apply','Open','Restore')){$connection=Get-DynamicCodexConnection}
    if($status.Error){$message='读取当前背景失败：'+$status.Error}
    if($PrepareOnly){$message='预览模式 · '+$message}
    [pscustomobject]@{Items=@(Get-DynamicWallpaperItems $StateRoot);Status=$status;Connection=$connection;SelectedId=$selected;Message=$message;EngineReport=$engineReport;Cancelled=$cancelled}
  }
  $null=$worker.AddScript($body.ToString()).AddArgument($ui.InstallRoot).AddArgument($ui.StateRoot).AddArgument($ui.ModuleRoot).AddArgument($Operation).AddArgument($Argument).AddArgument($Name).AddArgument($ui.PrepareOnly).AddArgument($queue).AddArgument($ui.Connection)
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
     $ui.Connection=$result.Connection
    Update-DynamicManagerConnectionBadge
    if($result.SelectedId -and $ui.Filter -ne 'All'){
      $selected=@($ui.Items|Where-Object Id -eq $result.SelectedId)
      if($selected.Count -and $selected[0].Kind -ne $ui.Filter){$ui.Filter=$selected[0].Kind}
    }
    if(-not $result.SelectedId -and $ui.Filter -eq 'Video' -and $ui.Items.Count -and @($ui.Items|Where-Object Kind -eq 'Video').Count -eq 0){$ui.Filter='Image'}
    if($ui.PendingOperation -in @('Import','SaveCurrent')){$ui.Source='Local'}
    if($ui.PendingOperation -eq 'EngineImport'){$ui.Source='WallpaperEngine'}
    if($ui.Filter -eq 'All'){
      $kinds=@(Get-DynamicVisibleWallpapers $ui.Items All $ui.Source|Select-Object -ExpandProperty Kind -Unique)
      if($kinds.Count -eq 1 -and $kinds[0] -in @('Image','Video')){$ui.Filter=$kinds[0]}
    }
    Update-DynamicManagerList $result.SelectedId
    if($result.Cancelled){Show-DynamicManagerToast $result.Message Info}
    elseif($ui.PendingOperation -eq 'Apply' -and -not $result.Status.Error){Show-DynamicManagerToast '壁纸已应用' Success}
    if($ui.PendingOperation -eq 'Refresh' -and $ui.HasCheckedConnection){
      if($ui.Connection.Connected){Show-DynamicManagerToast ('连接成功 · Codex '+$ui.Connection.Version) Success}else{Show-DynamicManagerToast '连接失败，请重试' Error}
    }
    if($ui.PendingOperation -eq 'Refresh'){$ui.HasCheckedConnection=$true}
  }catch{
    $errorMessage=Get-DynamicManagerErrorMessage $_.Exception
    $ui.Controls.StatusText.Text='操作未完成：'+$errorMessage
    Show-DynamicManagerToast ('操作未完成：'+$errorMessage) Error
  }finally{
    Set-DynamicConnectionChecking $false
    $ui.Worker.Dispose();$ui.Runspace.Dispose();$ui.Worker=$null;$ui.Runspace=$null;$ui.Async=$null
    $ui.Busy=$false;$ui.Controls.WorkProgress.Visibility='Collapsed';Update-DynamicManagerButtons
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
  foreach($name in @('ImportButton','ImageFilter','VideoFilter','WallpaperList','EmptyState','EmptyTitle','PreviewPlaceholder','PreviewImage','PreviewVideo','PlayButton','SelectedName','SelectedDetails','SelectedFormat','SelectedSize','SelectedImportedAt','SelectedStatus','PreviewNotice','ApplyButton','RenameButton','DeleteButton','WorkProgress','StatusText','OpenButton','RestoreButton')){$controls[$name]=$window.FindName($name)}
  foreach($name in @('LocalNavButton','EngineNavButton','EngineImportButton','EngineFolderButton','EnginePanel','EngineReport','SettingsButton','SettingsPanel','PreviewOverlay','ClosePreviewButton','PreviewApplyButton','EngineToolbar','LocalNavLabel','EngineNavLabel','LocalNavIcon','EngineNavIcon','NavThumbTransform','FilterThumb','FilterThumbTransform','ConnectionBadge','ConnectionBadgeText','ConnectionLoading','ConnectionSpinner')){$controls[$name]=$window.FindName($name)}
  foreach($name in @('ConnectionLabel','ConnectionDetail','ConfirmationOverlay','ConfirmationTitle','ConfirmationMessage','ConfirmAcceptButton','ConfirmCancelButton','ConfirmCloseButton','ToastPanel','ToastIcon','ToastIconBorder','ToastMessage')){$controls[$name]=$window.FindName($name)}
  $script:SkinManager=@{Window=$window;Controls=$controls;InstallRoot=$InstallRoot;StateRoot=$StateRoot;ModuleRoot=$PSScriptRoot;PrepareOnly=[bool]$PrepareOnly;Items=@();Status=[pscustomobject]@{CurrentId=$null;Paused=$false;HasExternalCurrent=$false;Error=$null};Selected=$null;Source='Local';Filter='All';Busy=$false;Playing=$false;PromptShown=$false;Worker=$null;Runspace=$null;Async=$null}
  $timer=New-Object Windows.Threading.DispatcherTimer;$timer.Interval=[timespan]::FromMilliseconds(120);$timer.Add_Tick({Complete-DynamicManagerWork});$script:SkinManager.Timer=$timer
  $script:SkinManager.Connection=[pscustomobject]@{Available=$false}
  . (Join-Path $PSScriptRoot 'update-ui.ps1')
  Initialize-DynamicUpdateUI
  $controls.ConfirmAcceptButton.Add_Click({Complete-DynamicManagerConfirmation $true})
  $controls.ConfirmCancelButton.Add_Click({Complete-DynamicManagerConfirmation $false})
  $controls.ConfirmCloseButton.Add_Click({Complete-DynamicManagerConfirmation $false})
  $controls.LocalNavButton.Add_Click({Set-DynamicManagerSource Local})
  $controls.EngineNavButton.Add_Click({Set-DynamicManagerSource WallpaperEngine})
  $controls.SettingsButton.Add_Click({$panel=$script:SkinManager.Controls.SettingsPanel;if($panel.Visibility -eq 'Visible'){$panel.Visibility='Collapsed'}else{$panel.Visibility='Visible'}})
  $controls.EngineImportButton.Add_Click({
    $ui=$script:SkinManager
    Show-DynamicManagerConfirmation '导入本地壁纸？' '查找本机 Steam 库中的 Wallpaper Engine 视频和图片，批量导入并保留原文件。' {Start-DynamicManagerWork EngineImport} -AcceptText '确认导入'
  })
  $controls.EngineFolderButton.Add_Click({
    Add-Type -AssemblyName System.Windows.Forms
    $dialog=New-Object Windows.Forms.FolderBrowserDialog
    $dialog.Description='选择 Wallpaper Engine 安装目录、壁纸父目录或单个项目目录；支持改名后的目录'
    try{if($dialog.ShowDialog() -eq 'OK'){Start-DynamicManagerWork EngineImport $dialog.SelectedPath}}finally{$dialog.Dispose()}
  })
  $controls.ClosePreviewButton.Add_Click({Close-DynamicCodexPreview})
  $controls.PreviewApplyButton.Add_Click({Confirm-DynamicWallpaperApply})
  Initialize-DynamicManagerDrag
  $controls.WallpaperList.Add_KeyDown({param($sender,$eventArgs);if($eventArgs.Key -eq 'Return'){Show-DynamicCodexPreview}})
  $window.Add_KeyDown({param($sender,$eventArgs);if($eventArgs.Key -eq 'Escape'){if($script:SkinManager.Controls.ConfirmationOverlay.Visibility -eq 'Visible'){Complete-DynamicManagerConfirmation $false}else{Close-DynamicCodexPreview;$script:SkinManager.Controls.SettingsPanel.Visibility='Collapsed'}}})
  $controls.WallpaperList.Add_SelectionChanged({Update-DynamicManagerSelection})
  $controls.ImageFilter.Add_Click({$script:SkinManager.Filter='Image';Update-DynamicManagerList})
  $controls.VideoFilter.Add_Click({$script:SkinManager.Filter='Video';Update-DynamicManagerList})
  $controls.ImportButton.Add_Click({
    $dialog=New-Object Microsoft.Win32.OpenFileDialog
    $dialog.Title='导入壁纸';$dialog.Filter='图片和视频|*.png;*.jpg;*.jpeg;*.webp;*.mp4;*.mov;*.m4v;*.wmv;*.avi;*.mkv;*.webm|静态图片|*.png;*.jpg;*.jpeg;*.webp|动态视频|*.mp4;*.mov;*.m4v;*.wmv;*.avi;*.mkv;*.webm'
    if($dialog.ShowDialog($script:SkinManager.Window)){Start-DynamicManagerWork Import $dialog.FileName}
  })
  $controls.ApplyButton.Add_Click({Confirm-DynamicWallpaperApply})
  $controls.RenameButton.Add_Click({Show-DynamicWallpaperRename})
  $controls.DeleteButton.Add_Click({
    $ui=$script:SkinManager
    $id=$ui.Selected.Id
    Show-DynamicManagerConfirmation -Title ('删除“'+$ui.Selected.Name+'”？') -Message '只删除库中的副本，原文件会保留。' -AcceptText '确认删除' -Action {Stop-DynamicManagerPreview;Start-DynamicManagerWork Delete $id}.GetNewClosure()
  })
  $controls.OpenButton.Add_Click({Start-DynamicManagerWork Refresh})
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
    if($script:SkinManager.ToastTimer){$script:SkinManager.ToastTimer.Stop()}
    $script:SkinManager.UpdateTimer.Stop();$script:SkinManager.UpdateStartupTimer.Stop()
    if($script:SkinManager.UpdateWorker){$script:SkinManager.UpdateWorker.Stop();$script:SkinManager.UpdateWorker.Dispose()}
    if($script:SkinManager.UpdateRunspace){$script:SkinManager.UpdateRunspace.Dispose()}
    if($script:SkinManager.Worker){$script:SkinManager.Worker.Dispose()};if($script:SkinManager.Runspace){$script:SkinManager.Runspace.Dispose()};$script:SkinManager=$null
  }
}

function Show-DynamicCodexPreview {
  $ui=$script:SkinManager
  if($ui.Busy -or -not $ui.Selected){return}
  $ui.Controls.PreviewOverlay.Visibility='Visible'
  Update-DynamicManagerSelection
  if($ui.Selected.Kind -eq 'Video' -and $ui.Selected.IsAvailable){
    $ui.Controls.PreviewVideo.Source=[uri]$ui.Selected.MediaPath
    $ui.Controls.PreviewVideo.Visibility='Visible';$ui.Controls.PreviewVideo.Play();$ui.Playing=$true;$ui.Controls.PlayButton.Content='暂停预览'
  }
}
function Close-DynamicCodexPreview {
  Stop-DynamicManagerPreview
  $script:SkinManager.Controls.PreviewOverlay.Visibility='Collapsed'
}

function Move-DynamicSelectionThumb {
  param($Transform,[ValidateSet('X','Y')][string]$Axis,[double]$To,[bool]$Animate=$true)
  $property=[Windows.Media.TranslateTransform]::XProperty;if($Axis -eq 'Y'){$property=[Windows.Media.TranslateTransform]::YProperty}
  $from=[double]$Transform.$Axis
  if([math]::Abs($from-$To) -lt 0.01 -and -not $Transform.HasAnimatedProperties){return}
  $Transform.BeginAnimation($property,$null);$Transform.$Axis=$To
  if($Animate){
    $animation=New-Object Windows.Media.Animation.DoubleAnimation
    $animation.From=$from;$animation.To=$To;$animation.Duration=[timespan]::FromMilliseconds(240)
    $ease=New-Object Windows.Media.Animation.CubicEase;$ease.EasingMode='EaseOut';$animation.EasingFunction=$ease
    $Transform.BeginAnimation($property,$animation)
  }
}
function Update-DynamicManagerFilterSlider {
  param([bool]$Animate=$true)
  $ui=$script:SkinManager
  if(-not $ui.Controls.FilterThumbTransform){return}
  $ui.Controls.FilterThumb.Visibility='Visible'
  if($ui.Filter -eq 'All'){$ui.Controls.FilterThumb.Visibility='Collapsed';return}
  $x=0;if($ui.Filter -eq 'Image'){$x=108}
  if($ui.FilterTarget -ne $ui.Filter -or -not $Animate){Move-DynamicSelectionThumb $ui.Controls.FilterThumbTransform X $x $Animate}
  $ui.FilterTarget=$ui.Filter
}
function Update-DynamicManagerNavigation {
  param([bool]$Animate=$true)
  $ui=$script:SkinManager
  if(-not $ui.Controls.NavThumbTransform){return}
  $engine=$ui.Source -eq 'WallpaperEngine'
  $ui.Controls.LocalNavLabel.Visibility='Visible';$ui.Controls.EngineNavLabel.Visibility='Collapsed'
  $ui.Controls.LocalNavIcon.Margin='0,0,12,0';$ui.Controls.EngineNavIcon.Margin='0'
  $ui.Controls.EngineToolbar.Visibility='Collapsed';$ui.Controls.EnginePanel.Visibility='Collapsed'
  $ui.Controls.ImportButton.Visibility='Visible'
  $y=0
  if($engine){
    $y=80;$ui.Controls.LocalNavLabel.Visibility='Collapsed';$ui.Controls.EngineNavLabel.Visibility='Visible'
    $ui.Controls.LocalNavIcon.Margin='0';$ui.Controls.EngineNavIcon.Margin='0,0,8,0'
    $ui.Controls.EngineToolbar.Visibility='Visible';$ui.Controls.ImportButton.Visibility='Collapsed'
    if(@(Get-DynamicVisibleWallpapers $ui.Items All WallpaperEngine).Count -eq 0){$ui.Controls.EnginePanel.Visibility='Visible';$ui.Controls.EmptyState.Visibility='Collapsed'}
  }
  if($ui.NavigationTarget -ne $ui.Source -or -not $Animate){Move-DynamicSelectionThumb $ui.Controls.NavThumbTransform Y $y $Animate}
  $ui.NavigationTarget=$ui.Source
}
function Set-DynamicManagerSource {
  param([ValidateSet('Local','WallpaperEngine')][string]$Source)
  $ui=$script:SkinManager
  if($ui.Busy){return}
  Close-DynamicCodexPreview
  $ui.Source=$Source
  Update-DynamicManagerList
}
function Update-DynamicManagerConnectionBadge {
  $ui=$script:SkinManager
  if(-not $ui.Controls.ConnectionBadge){return}
  $ui.Controls.ConnectionBadge.Visibility='Visible'
  $ui.Controls.ConnectionBadgeText.Text=[string][char]0x00d7
  $color='#E25563'
  if($ui.Connection.Connected){$color='#2CC17C';$ui.Controls.ConnectionBadgeText.Text=[string][char]0x2713}
  $ui.Controls.ConnectionBadge.Background=[Windows.Media.BrushConverter]::new().ConvertFromString($color)
  if($ui.Controls.ConnectionLabel){
    $ui.Controls.ConnectionLabel.Text='连接失败';$ui.Controls.ConnectionDetail.Text='未找到Codex'
    if($ui.Connection.Connected){$ui.Controls.ConnectionLabel.Text='连接成功';$ui.Controls.ConnectionDetail.Text='Codex '+$ui.Connection.Version}
  }
  $ui.Controls.OpenButton.ToolTip=$ui.Connection.Message+"`n单击重新检测"
}
function Set-DynamicConnectionChecking {
  param([bool]$Checking)
  $ui=$script:SkinManager
  if(-not $ui.Controls.ConnectionLoading){return}
  if($Checking){
    $ui.Controls.ConnectionLoading.Visibility='Visible';$ui.Controls.ConnectionBadge.Visibility='Collapsed'
    $ui.Controls.OpenButton.ToolTip='正在重新检测 Codex 连接…'
    if($ui.Controls.ConnectionLabel){$ui.Controls.ConnectionLabel.Text='正在连接…';$ui.Controls.ConnectionDetail.Text='请稍候'}
    $a=New-Object Windows.Media.Animation.DoubleAnimation 0,360,([Windows.Duration]::new([timespan]::FromSeconds(0.85)))
    $a.RepeatBehavior=[Windows.Media.Animation.RepeatBehavior]::Forever
    $ui.Controls.ConnectionSpinner.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty,$a)
  }else{
    $ui.Controls.ConnectionSpinner.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty,$null)
    $ui.Controls.ConnectionLoading.Visibility='Collapsed'
    Update-DynamicManagerConnectionBadge
  }
}

function Show-DynamicManagerConfirmation {
  param([string]$Title,[string]$Message,[scriptblock]$Action,[scriptblock]$CancelAction,[string]$AcceptText='确认')
  $ui=$script:SkinManager
  if($ui.Busy){return}
  $ui.ConfirmationAction=$Action;$ui.ConfirmationCancel=$CancelAction
  $ui.Controls.ConfirmationTitle.Text=$Title;$ui.Controls.ConfirmationMessage.Text=$Message
  $ui.Controls.ConfirmAcceptButton.Content=$AcceptText;$ui.Controls.ConfirmationOverlay.Visibility='Visible'
}
function Complete-DynamicManagerConfirmation {
  param([bool]$Accepted)
  $ui=$script:SkinManager
  $action=$ui.ConfirmationCancel;if($Accepted){$action=$ui.ConfirmationAction}
  $ui.ConfirmationAction=$null;$ui.ConfirmationCancel=$null;$ui.Controls.ConfirmationOverlay.Visibility='Collapsed'
  if($action){& $action}
}
function Show-DynamicManagerToast {
  param([string]$Message,[ValidateSet('Success','Error','Info')][string]$Kind='Success')
  $ui=$script:SkinManager
  $color='#2CC17C';$glyph=[string][char]0x2713
  if($Kind -eq 'Error'){$color='#F03545';$glyph=[string][char]0x00d7}
  if($Kind -eq 'Info'){$color='#657BEF';$glyph='i'}
  $ui.Controls.ToastMessage.Text=$Message;$ui.Controls.ToastIcon.Text=$glyph
  $ui.Controls.ToastIconBorder.Background=[Windows.Media.BrushConverter]::new().ConvertFromString($color)
  $ui.Controls.ToastPanel.Visibility='Visible'
  if(-not $ui.ToastTimer){$ui.ToastTimer=New-Object Windows.Threading.DispatcherTimer;$ui.ToastTimer.Interval=[timespan]::FromSeconds(5);$ui.ToastTimer.Add_Tick({$script:SkinManager.Controls.ToastPanel.Visibility='Collapsed';$script:SkinManager.ToastTimer.Stop()})}
  $ui.ToastTimer.Stop();$ui.ToastTimer.Start()
}
function Confirm-DynamicWallpaperApply {
  $ui=$script:SkinManager
  if(-not $ui.Selected -or $ui.PrepareOnly -or $ui.Busy){return}
  $id=$ui.Selected.Id
  Show-DynamicManagerConfirmation -Title '应用这张壁纸？' -Message '保存当前工作后继续，可能需要重启 Codex。' -AcceptText '确认应用' -Action {Start-DynamicManagerWork Apply $id}.GetNewClosure()
}

function Get-DynamicProportionalBounds {
  param([double]$Left,[double]$Top,[double]$Width,[double]$Height,[ValidateSet('TopLeft','TopRight','BottomLeft','BottomRight')][string]$Corner,[double]$DeltaX,[double]$DeltaY)
  $dx=$DeltaX;if($Corner -like '*Left'){$dx=-$dx}
  $dy=$DeltaY;if($Corner -like 'Top*'){$dy=-$dy}
  $change=$dx
  if([math]::Abs($dy/$Height) -gt [math]::Abs($dx/$Width)){$change=$dy*12/7}
  $newWidth=[math]::Max(900,$Width+$change);$newHeight=$newWidth*7/12
  if($Corner -like '*Left'){$Left+=$Width-$newWidth}
  if($Corner -like 'Top*'){$Top+=$Height-$newHeight}
  [pscustomobject]@{Left=$Left;Top=$Top;Width=$newWidth;Height=$newHeight}
}
function Switch-DynamicManagerZoom {
  param($Window)
  if($Window.Tag -and $Window.Tag.ZoomRestore){
    $b=$Window.Tag.ZoomRestore;$Window.Left=$b.Left;$Window.Top=$b.Top;$Window.Width=$b.Width;$Window.Height=$b.Height;$Window.Tag=$null
  }else{
    $Window.Tag=@{ZoomRestore=[pscustomobject]@{Left=$Window.Left;Top=$Window.Top;Width=$Window.Width;Height=$Window.Height}}
    $area=[Windows.SystemParameters]::WorkArea
    $width=[math]::Max(900,[math]::Min($area.Width-16,($area.Height-16)*12/7))
    $Window.Width=$width;$Window.Height=$width*7/12
    $Window.Left=$area.Left+($area.Width-$Window.Width)/2;$Window.Top=$area.Top+($area.Height-$Window.Height)/2
  }
}

function Get-DynamicDragRegion {
  param($Element)
  while($null -ne $Element){
    if($Element -is [Windows.Controls.ListBoxItem]){return [pscustomobject]@{Kind='Card';Card=$Element}}
    if($Element -is [Windows.FrameworkElement] -and $Element.Name -eq 'GalleryRegion'){return [pscustomobject]@{Kind='Excluded';Card=$null}}
    if($Element -is [Windows.Controls.ListBox] -or $Element -is [Windows.Controls.Primitives.Thumb] -or $Element -is [Windows.Controls.Primitives.TextBoxBase] -or $Element -is [Windows.Controls.Primitives.ScrollBar]){return [pscustomobject]@{Kind='Excluded';Card=$null}}
    try{$Element=[Windows.Media.VisualTreeHelper]::GetParent($Element)}catch{$Element=[Windows.LogicalTreeHelper]::GetParent($Element)}
  }
  [pscustomobject]@{Kind='Window';Card=$null}
}
function Test-DynamicLongDrag {
  param([double]$ElapsedMilliseconds,[double]$DeltaX,[double]$DeltaY)
  return ($ElapsedMilliseconds -ge 350 -and ($DeltaX*$DeltaX+$DeltaY*$DeltaY) -ge 36)
}
function Invoke-DynamicManagerCardSwap {
  param([string]$FirstId,[string]$SecondId)
  $ui=$script:SkinManager
  if($ui.Busy -or $FirstId -eq $SecondId){return}
  $visible=@($ui.Controls.WallpaperList.ItemsSource|ForEach-Object {$_.Id})
  if($visible -notcontains $FirstId -or $visible -notcontains $SecondId){return}
  Start-DynamicManagerWork Swap $FirstId $SecondId
}
function Initialize-DynamicManagerDrag {
  $ui=$script:SkinManager;$window=$ui.Window;$list=$ui.Controls.WallpaperList
  $list.AllowDrop=$true
  $window.Add_PreviewMouseLeftButtonDown({param($sender,$e)
    $ui=$script:SkinManager
    $region=Get-DynamicDragRegion $e.OriginalSource
    $ui.DragGesture=$null;$ui.SuppressPreview=$false
    if($region.Kind -eq 'Excluded' -or ($region.Kind -eq 'Card' -and $ui.Busy)){return}
    $point=$e.GetPosition($ui.Window)
    $ui.DragGesture=@{Region=$region;Point=$point;ScreenPoint=$ui.Window.PointToScreen($point);Left=$ui.Window.Left;Top=$ui.Window.Top;Moving=$false;Watch=[Diagnostics.Stopwatch]::StartNew()}
  })
  $window.Add_PreviewMouseMove({param($sender,$e)
    $ui=$script:SkinManager;$gesture=$ui.DragGesture
    if(-not $gesture -or $e.LeftButton -ne 'Pressed'){return}
    $point=$e.GetPosition($ui.Window)
    if(-not $gesture.Moving -and -not(Test-DynamicLongDrag $gesture.Watch.Elapsed.TotalMilliseconds ($point.X-$gesture.Point.X) ($point.Y-$gesture.Point.Y))){return}
    $ui.SuppressPreview=$true;$e.Handled=$true
    if($gesture.Region.Kind -eq 'Window'){
      $screenPoint=$ui.Window.PointToScreen($point)
      if(-not $gesture.Moving){
        # Capture cancels a pressed button and keeps movement routed to this window.
        $gesture.Moving=$true;[Windows.Input.Mouse]::Capture($ui.Window,[Windows.Input.CaptureMode]::SubTree)|Out-Null
      }
      $dpi=[Windows.Media.VisualTreeHelper]::GetDpi($ui.Window)
      Move-DynamicWindowFromPointer $ui.Window $gesture $screenPoint $dpi.DpiScaleX $dpi.DpiScaleY
    }else{
      $ui.DragGesture=$null
      [Windows.Input.Mouse]::Capture($null)|Out-Null
      $card=$gesture.Region.Card
      $ui.Controls.WallpaperList.SelectedItem=$card.Content
      $data=New-Object Windows.DataObject
      $data.SetData('CodexWallpaperId',[string]$card.Content.Id)
      $card.Opacity=0.6
      try{[Windows.DragDrop]::DoDragDrop($card,$data,[Windows.DragDropEffects]::Move)|Out-Null}finally{$card.Opacity=1}
    }
  })
  $window.Add_PreviewMouseLeftButtonUp({param($sender,$e)
    $ui=$script:SkinManager
    if($ui.DragGesture -and $ui.DragGesture.Moving){[Windows.Input.Mouse]::Capture($null)|Out-Null}
    $ui.DragGesture=$null
    if($ui.SuppressPreview){$e.Handled=$true;$ui.SuppressPreview=$false;return}
    $region=Get-DynamicDragRegion $e.OriginalSource
    if($region.Kind -eq 'Card'){$ui.Controls.WallpaperList.SelectedItem=$region.Card.Content;Show-DynamicCodexPreview}
  })
  $window.Add_Deactivated({if($script:SkinManager){if($script:SkinManager.DragGesture -and $script:SkinManager.DragGesture.Moving){[Windows.Input.Mouse]::Capture($null)|Out-Null};$script:SkinManager.DragGesture=$null}})
  $list.Add_DragOver({param($sender,$e)
    $region=Get-DynamicDragRegion $e.OriginalSource
    $e.Effects=[Windows.DragDropEffects]::None
    if(-not $script:SkinManager.Busy -and $region.Kind -eq 'Card' -and $e.Data.GetDataPresent('CodexWallpaperId')){$e.Effects=[Windows.DragDropEffects]::Move}
    $e.Handled=$true
  })
  $list.Add_Drop({param($sender,$e)
    $ui=$script:SkinManager;$ui.SuppressPreview=$true;$ui.DragGesture=$null;$e.Handled=$true
    $region=Get-DynamicDragRegion $e.OriginalSource
    if($region.Kind -ne 'Card' -or -not $e.Data.GetDataPresent('CodexWallpaperId')){return}
    try{Invoke-DynamicManagerCardSwap ([string]$e.Data.GetData('CodexWallpaperId')) ([string]$region.Card.Content.Id)}catch{Show-DynamicManagerToast ('交换失败：'+$_.Exception.Message) Error}
  })
}

function Move-DynamicWindowFromPointer {
  param($Window,$Gesture,$ScreenPoint,[double]$ScaleX,[double]$ScaleY)
  $Window.Left=$Gesture.Left+($ScreenPoint.X-$Gesture.ScreenPoint.X)/$ScaleX
  $Window.Top=$Gesture.Top+($ScreenPoint.Y-$Gesture.ScreenPoint.Y)/$ScaleY
}
