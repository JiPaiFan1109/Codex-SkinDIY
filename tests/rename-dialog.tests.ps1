$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/skin-manager.ps1')
$owner=New-DynamicSkinManagerWindow
try {
  foreach($accept in @($false,$true)){
    $dialog=New-DynamicRenameWindow -Owner $owner -Name 'Original'
    $dialog.ShowActivated=$false;$dialog.WindowStartupLocation='Manual';$dialog.Left=-10000;$dialog.Top=-10000
    $row=$dialog.Content.Children[3];$cancel=$row.Children[0];$save=$row.Children[1]
    $dialog.Tag.Text='   '
    if($save.IsEnabled){throw 'Whitespace name must disable save'}
    $dialog.Tag.Text='Renamed'
    if(-not $save.IsEnabled -or -not $save.IsDefault -or -not $cancel.IsCancel){throw 'Rename keyboard actions or validation missing'}
    $dialog.Add_ContentRendered({
      if($accept){$save.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))}
      else{$cancel.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))}
    }.GetNewClosure())
    $result=$dialog.ShowDialog()
    if([bool]$result -ne $accept){throw 'Rename modal result does not match action'}
    if($accept -and $dialog.Tag.Text -ne 'Renamed'){throw 'Rename result lost input'}
  }
  'PASS rename whitespace validation, cancel and save modal results'
}finally{$owner.Close()}
