$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. "$repo/scripts/skin-manager.ps1"
function Assert($c,$m){if(-not $c){throw $m}}
Assert ([bool](Get-Command Get-DynamicProportionalBounds -ErrorAction SilentlyContinue)) 'Corner proportional resize is missing'
foreach($corner in @('TopLeft','TopRight','BottomLeft','BottomRight')){
 $dx=120;$dy=70;if($corner -like '*Left'){$dx=-120};if($corner -like 'Top*'){$dy=-70}
 $b=Get-DynamicProportionalBounds -Left 200 -Top 150 -Width 1200 -Height 700 -Corner $corner -DeltaX $dx -DeltaY $dy
 Assert ([math]::Abs($b.Width/$b.Height-12.0/7) -lt 0.00001) 'Aspect ratio changed'
 Assert ($b.Width -eq 1320 -and $b.Height -eq 770) 'Resize scale was not proportional'
 if($corner -like '*Left'){Assert ([math]::Abs($b.Left+$b.Width-1400) -lt .01) 'Opposite horizontal edge moved'}else{Assert ($b.Left -eq 200) 'Left anchor moved'}
 if($corner -like 'Top*'){Assert ([math]::Abs($b.Top+$b.Height-850) -lt .01) 'Opposite vertical edge moved'}else{Assert ($b.Top -eq 150) 'Top anchor moved'}
 $small=Get-DynamicProportionalBounds 200 150 1200 700 $corner (-$dx*20) (-$dy*20)
 Assert ($small.Width -eq 900 -and $small.Height -eq 525) 'Minimum size broke aspect ratio'
}
$w=New-DynamicSkinManagerWindow
try{
 $c=@{};foreach($m in [regex]::Matches([IO.File]::ReadAllText("$repo/scripts/skin-manager.xaml"),'x:Name="([^"]+)"')){$c[$m.Groups[1].Value]=$w.FindName($m.Groups[1].Value)}
 foreach($removed in @('OpenCodexButton','AllFilter','DetectButton','SaveCurrentButton','LibrarySummary')){Assert ($null -eq $w.FindName($removed)) 'Removed management entry is still present'}
 foreach($corner in @('TopLeft','TopRight','BottomLeft','BottomRight')){Assert ($c[('Resize'+$corner)] -is [Windows.Controls.Primitives.Thumb]) 'Missing usable corner handle'}
 foreach($corner in @('TopLeft','TopRight','BottomLeft','BottomRight')){
  $w.Left=200;$w.Top=150;$w.Width=1200;$w.Height=700
  $dx=120;$dy=70;if($corner -like '*Left'){$dx=-120};if($corner -like 'Top*'){$dy=-70}
  $event=New-Object Windows.Controls.Primitives.DragDeltaEventArgs $dx,$dy
  $event.RoutedEvent=[Windows.Controls.Primitives.Thumb]::DragDeltaEvent
  $c[('Resize'+$corner)].RaiseEvent($event)
  Assert ($w.Width -eq 1320 -and $w.Height -eq 770) 'Corner drag event did not resize the actual window'
 }
 $script:SkinManager=@{Window=$w;Controls=$c;Items=@();Source='Local';Filter='Image';Busy=$false;Selected=$null;Status=[pscustomobject]@{CurrentId=$null;HasExternalCurrent=$false;Error=$null};Connection=[pscustomobject]@{Available=$false};PrepareOnly=$true}
 Update-DynamicManagerFilterSlider -Animate:$false
 Set-DynamicManagerSource WallpaperEngine
 Assert ($script:SkinManager.Filter -eq 'Image' -and $c.FilterThumbTransform.X -eq 108 -and -not $c.FilterThumbTransform.HasAnimatedProperties) 'Source navigation changed or animated media filter'
 Set-DynamicManagerSource Local
 Assert ($script:SkinManager.Filter -eq 'Image') 'Returning to local changed media filter'
 $v=$w.Content
 $v.Measure([Windows.Size]::new(1440,840));$v.Arrange([Windows.Rect]::new(0,0,1440,840));$v.UpdateLayout()
 $first=$c.ApplyButton.TransformToAncestor($v).TransformBounds([Windows.Rect]::new(0,0,$c.ApplyButton.ActualWidth,$c.ApplyButton.ActualHeight))
 $v.Measure([Windows.Size]::new(900,525));$v.Arrange([Windows.Rect]::new(0,0,900,525));$v.UpdateLayout()
 $small=$c.ApplyButton.TransformToAncestor($v).TransformBounds([Windows.Rect]::new(0,0,$c.ApplyButton.ActualWidth,$c.ApplyButton.ActualHeight))
 Assert ([math]::Abs($small.Width/$first.Width-.625) -lt .01 -and [math]::Abs($small.Height/$first.Height-.625) -lt .01) 'Button does not scale uniformly at minimum window size'
 Assert ($small.Left -ge 0 -and $small.Top -ge 0 -and $small.Right -le 900 -and $small.Bottom -le 525) 'Apply button clips at minimum window size'
 Assert (-not [string]::IsNullOrWhiteSpace([Windows.Automation.AutomationProperties]::GetName($c.ApplyButton))) 'Apply action has no accessible name'
 Assert ($null -ne $c.EngineNavImage.Source -and $null -ne $c.ApplyIcon.Source) 'Provided icon assets failed to load'
 'PASS independent source filter, all four anchored resize corners, minimum size, uniform control scale and icon assets'
}finally{$w.Close();$script:SkinManager=$null}
