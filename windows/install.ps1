param(
  [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'Devvy'),
  [string]$ReleaseVersion = 'v4.1.0',
  [string]$ReleaseAssetUrl = '',
  [string]$ReleaseSha256 = '',
  [string]$SourceDir = ''
)
$ErrorActionPreference = 'Stop'
$TaskName = 'Devvy'
$Repo = 'https://github.com/sonawaneutkarsh/devvy'
$asset = 'devvy-windows-x86_64.zip'
$temp = Join-Path ([IO.Path]::GetTempPath()) ('devvy-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $temp | Out-Null
try {
  if (-not [Environment]::Is64BitOperatingSystem) { throw 'Devvy Windows currently requires Windows x64.' }
  if ([string]::IsNullOrWhiteSpace($SourceDir)) {
    $url = if ($ReleaseAssetUrl) { $ReleaseAssetUrl } else { "$Repo/releases/download/$ReleaseVersion/$asset" }
    $archive = Join-Path $temp $asset
    $checksumUrl = "$url.sha256"
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $archive
    $expected = if ($ReleaseSha256) { $ReleaseSha256.ToLowerInvariant() } else {
      (Invoke-WebRequest -UseBasicParsing -Uri $checksumUrl).Content.Trim() -split '\s+' | Select-Object -First 1
    }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw "Release checksum mismatch. Expected $expected, got $actual." }
    Expand-Archive -LiteralPath $archive -DestinationPath $temp -Force
    $SourceDir = Join-Path $temp 'devvy'
  }
  $node = Join-Path $SourceDir 'runtime\node.exe'
  $daemon = Join-Path $SourceDir 'daemon\daemon.mjs'
  $vsix = Get-ChildItem -LiteralPath $SourceDir -Filter '*.vsix' | Select-Object -First 1
  if (-not (Test-Path -LiteralPath $node) -or -not (Test-Path -LiteralPath $daemon)) { throw 'The Devvy payload is incomplete.' }
  $nodeVersion = & $node -p 'process.versions.node'
  if ([int]($nodeVersion -split '\.')[0] -lt 18) { throw "Bundled Node.js $nodeVersion is too old." }

  if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) { Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue; Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false }
  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
  Copy-Item -Path (Join-Path $SourceDir '*') -Destination $InstallDir -Recurse -Force
  $runner = Join-Path $InstallDir 'windows\run-daemon.ps1'
  $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$runner`" -InstallDir `"$InstallDir`""
  $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
  $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances Ignore
  Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Description 'Devvy Discord presence daemon' | Out-Null
  Start-ScheduledTask -TaskName $TaskName

  $opencode = Join-Path $HOME '.config\opencode\plugins\discord-presence.ts'
  $commandcode = Join-Path $HOME '.commandcode\mods\discord-presence.ts'
  if (Get-Command opencode -ErrorAction SilentlyContinue) { New-Item -ItemType Directory -Force (Split-Path $opencode) | Out-Null; Copy-Item (Join-Path $InstallDir 'integrations\opencode\discord-presence.ts') $opencode -Force }
  if (Get-Command commandcode -ErrorAction SilentlyContinue) { New-Item -ItemType Directory -Force (Split-Path $commandcode) | Out-Null; Copy-Item (Join-Path $InstallDir 'integrations\commandcode\discord-presence.ts') $commandcode -Force }

  $cli = & (Join-Path $InstallDir 'scripts\vscode-cli.ps1')
  if ($cli -and $vsix) { & $cli --install-extension $vsix.FullName --force | Out-Null; Write-Host 'Devvy: VS Code extension installed.' }
  elseif (-not $cli) { Write-Host "Devvy: VS Code was not detected. The daemon is installed; supported integrations can still connect to it." }
  for ($i = 0; $i -lt 30; $i++) { try { if ((Invoke-RestMethod 'http://127.0.0.1:17377/healthz').ok) { Write-Host "Devvy $ReleaseVersion installed successfully."; exit 0 } } catch {}; Start-Sleep -Milliseconds 250 }
  throw 'Devvy started but did not pass its health check.'
} finally { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
