$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../engine/scripts/theme-windows.ps1')
. (Join-Path $PSScriptRoot '../scripts/skin-manager.ps1')
$window=New-DynamicSkinManagerWindow
try{
  $window.ShowActivated=$false;$window.ShowInTaskbar=$false;$window.Opacity=0;$window.Show()
  $surface=$window.Content
  $surface.Measure([Windows.Size]::new(1440,840));$surface.Arrange([Windows.Rect]::new(0,0,1440,840));$surface.UpdateLayout()
  $drawing=[Windows.Media.DrawingVisual]::new();$dc=$drawing.RenderOpen()
  $dc.DrawRectangle([Windows.Media.BrushConverter]::new().ConvertFromString('#EDF5FC'),$null,[Windows.Rect]::new(0,0,600,390))
  $row=0
  foreach($state in @('Normal','MouseOver','Pressed','Disabled')){
    $label=[Windows.Media.FormattedText]::new($state,[Globalization.CultureInfo]::InvariantCulture,[Windows.FlowDirection]::LeftToRight,[Windows.Media.Typeface]::new('Segoe UI'),13,[Windows.Media.Brushes]::DarkSlateGray,1.0)
    $dc.DrawText($label,[Windows.Point]::new(18,30+$row*92))
    $column=0
    foreach($name in @('ImportButton','ApplyButton')){
      $button=$window.FindName($name);$button.IsEnabled=($state -ne 'Disabled');$button.ApplyTemplate()|Out-Null
      $button.UpdateLayout()
      if(-not [Windows.VisualStateManager]::GoToState($button,$state,$false)){throw "Missing visual state $state"}
      $frame=[Windows.Threading.DispatcherFrame]::new();$timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[timespan]::FromMilliseconds(250);$timer.Add_Tick({$timer.Stop();$frame.Continue=$false}.GetNewClosure());$timer.Start();[Windows.Threading.Dispatcher]::PushFrame($frame)
      $button.UpdateLayout()
      [Windows.VisualStateManager]::GoToState($button,$state,$false)|Out-Null
      $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$button.ActualWidth,[int]$button.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($button.Template.FindName('ActionRoot',$button));$bitmap.Freeze()
      $dc.DrawImage($bitmap,[Windows.Rect]::new(120+$column*210,18+$row*92,$button.ActualWidth,$button.ActualHeight))
      if($state -eq 'Disabled' -and $button.Template.FindName('Glow',$button).Opacity -ne 0){throw 'Disabled button retains hover glow'}
      if($state -eq 'Pressed' -and [Math]::Abs($button.Template.FindName('ButtonScale',$button).ScaleX-.985) -gt .001){throw 'Pressed feedback missing'}
      $column++
    }
    $row++
  }
  $dc.Close()
  $output=[Windows.Media.Imaging.RenderTargetBitmap]::new(600,390,96,96,[Windows.Media.PixelFormats]::Pbgra32);$output.Render($drawing)
  $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($output));$stream=[IO.File]::Create((Join-Path $PSScriptRoot '../previews/button-states.png'));try{$encoder.Save($stream)}finally{$stream.Dispose()}
  'PASS: normal, hover, pressed, disabled button visuals'
}finally{$window.Close()}
