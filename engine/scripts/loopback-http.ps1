function Invoke-DreamSkinLoopbackJson {
  param([int]$Port,[ValidateSet('/json/version','/json/list')][string]$Resource,[int]$TimeoutMilliseconds=1500)
  if($Port -lt 1024 -or $Port -gt 65535){throw 'Invalid loopback port'}
  $request=[Net.HttpWebRequest]::Create("http://127.0.0.1:$Port$Resource")
  # Local CDP must never wait for proxy discovery or use the system proxy.
  $request.Proxy=$null
  $request.AllowAutoRedirect=$false
  $request.Timeout=$TimeoutMilliseconds
  $request.ReadWriteTimeout=$TimeoutMilliseconds
  $response=$null;$reader=$null
  try {
    $response=$request.GetResponse()
    if([int]$response.StatusCode -ne 200){throw 'Unexpected CDP response'}
    $reader=[IO.StreamReader]::new($response.GetResponseStream())
    return ($reader.ReadToEnd() | ConvertFrom-Json -ErrorAction Stop)
  } finally {
    if($reader){$reader.Dispose()}
    if($response){$response.Dispose()}
  }
}
