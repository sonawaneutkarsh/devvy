param([string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'Devvy'))
$ErrorActionPreference = 'SilentlyContinue'
if (Get-ScheduledTask -TaskName 'Devvy') { Stop-ScheduledTask -TaskName 'Devvy'; Unregister-ScheduledTask -TaskName 'Devvy' -Confirm:$false }
$cliScript = Join-Path $InstallDir 'scripts\vscode-cli.ps1'
if (Test-Path $cliScript) { $cli = & $cliScript; if ($cli) { & $cli --uninstall-extension sonawaneutkarsh.devvy | Out-Null } }
Remove-Item (Join-Path $HOME '.config\opencode\plugins\discord-presence.ts'), (Join-Path $HOME '.commandcode\mods\discord-presence.ts') -Force
Remove-Item $InstallDir -Recurse -Force
Write-Host 'Devvy uninstalled. Unrelated user files were not changed.'
