param(
  [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'Devvy')
)
$ErrorActionPreference = 'Stop'
$node = Join-Path $InstallDir 'runtime\node.exe'
$daemon = Join-Path $InstallDir 'daemon\daemon.mjs'
$logDir = Join-Path $InstallDir 'daemon\.live-ipc'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

if (-not (Test-Path -LiteralPath $node) -or -not (Test-Path -LiteralPath $daemon)) { exit 1 }
try {
  $version = & $node -p 'process.versions.node'
  if ([int]($version -split '\.')[0] -lt 18) { exit 1 }
} catch { exit 1 }

while ($true) {
  try {
    $health = Invoke-RestMethod -Uri 'http://127.0.0.1:17377/healthz' -TimeoutSec 1
    if ($health.ok -eq $true -and $health.service -eq 'devvy') { exit 0 }
  } catch { }
  $proc = Start-Process -FilePath $node -ArgumentList @($daemon) -WorkingDirectory (Join-Path $InstallDir 'daemon') `
    -RedirectStandardOutput (Join-Path $logDir 'task.stdout.log') `
    -RedirectStandardError (Join-Path $logDir 'task.stderr.log') -PassThru -WindowStyle Hidden
  $proc.WaitForExit()
  Start-Sleep -Seconds 2
}
