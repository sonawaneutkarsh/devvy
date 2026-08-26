$candidates = @(
  (Get-Command code.cmd -ErrorAction SilentlyContinue).Source,
  (Get-Command code -ErrorAction SilentlyContinue).Source,
  (Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin\code.cmd'),
  (Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code Insiders\bin\code-insiders.cmd'),
  (Join-Path ${env:ProgramFiles} 'Microsoft VS Code\bin\code.cmd'),
  (Join-Path ${env:ProgramFiles} 'Microsoft VS Code Insiders\bin\code-insiders.cmd')
)
$candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
