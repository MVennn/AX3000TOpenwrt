# recover-run.ps1 - upload recover-now.sh to the router and run it
# Usage: double-click recover-run.cmd, or run this file in PowerShell
# Requires: Windows 10/11 built-in OpenSSH client (ssh.exe)

$ErrorActionPreference = 'Stop'
# 可用环境变量 ROUTER_IP 覆盖；默认值只是示例
$router = if ($env:ROUTER_IP) { $env:ROUTER_IP } else { '10.0.0.1' }
# recover-now.sh lives one level up (recovery/)
$localScript = Join-Path (Split-Path $PSScriptRoot -Parent) 'recover-now.sh'
$outFile = Join-Path $PSScriptRoot 'recover-output.txt'

Write-Host ''
Write-Host '=== ShellCrash Recovery ===' -ForegroundColor Cyan
Write-Host "Router: $router"
Write-Host ''

$ssh = Get-Command ssh -ErrorAction SilentlyContinue
if (-not $ssh) {
    Write-Host 'ssh.exe not found. Use Git Bash instead:'
    Write-Host '  cd <仓库根>/recovery'
    Write-Host '  cat recover-now.sh | /tmp/owrt/rsh.sh "cat > /tmp/recover-now.sh && ash /tmp/recover-now.sh"'
    exit 1
}
if (-not (Test-Path $localScript)) {
    Write-Host "Script not found: $localScript" -ForegroundColor Red
    exit 1
}

Write-Host 'Checking router reachability...' -ForegroundColor Cyan
if (-not (Test-Connection -ComputerName $router -Count 1 -Quiet)) {
    Write-Host "Cannot ping $router." -ForegroundColor Red
    Write-Host 'Connect the PC to the router LAN/WiFi first (no internet needed).'
    exit 1
}
Write-Host 'Router reachable OK' -ForegroundColor Green
Write-Host ''

# Force UTF-8 both ways so Chinese text in the remote output is not garbled
$OutputEncoding = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

# Read as UTF-8 explicitly: PowerShell 5.1 would otherwise decode the file as ANSI
# and mangle the Chinese/emoji strings used inside the recovery script.
$content = [IO.File]::ReadAllText($localScript, [Text.Encoding]::UTF8) -replace "`r`n", "`n"

Write-Host 'You will be asked for the root password (input is hidden).' -ForegroundColor Yellow
Write-Host ''

$sshArgs = @(
    '-o', 'StrictHostKeyChecking=no',
    '-o', 'UserKnownHostsFile=NUL',
    '-o', 'LogLevel=ERROR',
    '-o', 'PubkeyAuthentication=no',
    '-o', 'PreferredAuthentications=password',
    '-o', 'RequestTTY=no',
    "root@$router",
    'cat > /tmp/recover-now.sh && ash /tmp/recover-now.sh'
)

# Windows PowerShell 5.1 wraps native stderr as ErrorRecord; with the global
# 'Stop' preference the first ssh warning would abort the whole recovery.
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $content | & $ssh.Source @sshArgs 2>&1 | Tee-Object -FilePath $outFile
} finally {
    $ErrorActionPreference = $prevEap
}

Write-Host ''
Write-Host "Output saved to: $outFile" -ForegroundColor Cyan
Write-Host 'Send this output (or /root/recover-last.log on the router) back to continue.'
Write-Host ''
