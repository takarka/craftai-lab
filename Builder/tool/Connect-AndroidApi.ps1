param([string]$DeviceId = 'af54415c', [switch]$Watch)

$ErrorActionPreference = 'Stop'
$adbPath = Join-Path $env:LOCALAPPDATA 'Android\sdk\platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $adbPath)) {
  $adbPath = (Get-Command adb -ErrorAction Stop).Source
}

Write-Host 'Builder: connecting Android API'
do {
  & $adbPath -s $DeviceId reverse tcp:5001 tcp:5001
  if ($LASTEXITCODE -eq 0) {
    Write-Host 'Builder: Android localhost:5001 is connected to the local API.'
  } elseif (-not $Watch) {
    throw 'Cannot connect the Android device to the local API. Check the USB connection and USB debugging.'
  }
  if ($Watch) { Start-Sleep -Seconds 5 }
} while ($Watch)
