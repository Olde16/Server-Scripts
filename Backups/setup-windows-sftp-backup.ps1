#Requires -RunAsAdministrator

<#
Configures an EXISTING Windows user as an SFTP source for the Linux
Backups/backup-windows.sh script.

This script does not create users and does not change NTFS permissions.
The administrator decides which paths the existing user can read.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$UserName,

    [string]$AllowFrom = ''
)

$ErrorActionPreference = 'Stop'
$NewLine = [Environment]::NewLine

Write-Host "[+] Checking existing user..."
$user = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
if (-not $user) {
    throw "User '$UserName' does not exist. Create it first and run this script again."
}

Write-Host "[+] Checking OpenSSH Server..."
$capability = Get-WindowsCapability -Online |
    Where-Object { $_.Name -like 'OpenSSH.Server*' } |
    Select-Object -First 1

if (-not $capability) {
    throw 'OpenSSH Server capability was not found on this Windows installation.'
}

if ($capability.State -ne 'Installed') {
    Write-Host '[+] Installing OpenSSH Server...'
    Add-WindowsCapability -Online -Name $capability.Name | Out-Host
}

$sshdConfig = Join-Path $env:ProgramData 'ssh\sshd_config'
$sshdExe = Join-Path $env:WINDIR 'System32\OpenSSH\sshd.exe'

if (-not (Test-Path $sshdConfig)) {
    throw "OpenSSH configuration was not found at $sshdConfig."
}
if (-not (Test-Path $sshdExe)) {
    throw "OpenSSH server executable was not found at $sshdExe."
}

$backupConfig = "$sshdConfig.backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
Copy-Item -LiteralPath $sshdConfig -Destination $backupConfig -Force
Write-Host "[+] Backed up sshd_config to $backupConfig"

$config = Get-Content -LiteralPath $sshdConfig -Raw

# Make sure the normal SFTP subsystem exists.
if ($config -notmatch '(?m)^\s*Subsystem\s+sftp\s+') {
    Add-Content -LiteralPath $sshdConfig -Value "\${NewLine}Subsystem sftp sftp-server.exe\${NewLine}"
    $config = Get-Content -LiteralPath $sshdConfig -Raw
}

$begin = "# BEGIN Server-Scripts backup SFTP user: $UserName"
$end = "# END Server-Scripts backup SFTP user: $UserName"

# Remove a block previously managed by this script, making reruns idempotent.
$blockPattern = '(?ms)^' + [regex]::Escape($begin) + '\r?\n.*?^' + [regex]::Escape($end) + '\r?\n?'
$config = [regex]::Replace($config, $blockPattern, '').TrimEnd() + $NewLine

$matchLine = "Match User $UserName"
if ($AllowFrom) {
    if ($AllowFrom -notmatch '^(?:\d{1,3}\.){3}\d{1,3}$') {
        throw 'AllowFrom must be an IPv4 address, for example 192.168.1.5.'
    }
    $matchLine += " Address $AllowFrom"
}

$managedBlock = @(
    $begin
    $matchLine
    '    ForceCommand internal-sftp'
    '    PermitTTY no'
    '    AllowTcpForwarding no'
    '    X11Forwarding no'
    $end
) -join $NewLine

$config = $config.TrimEnd() + $NewLine + $NewLine + $managedBlock + $NewLine
[System.IO.File]::WriteAllText(
    $sshdConfig,
    $config,
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Host '[+] Validating sshd configuration...'
& $sshdExe -t -f $sshdConfig
if ($LASTEXITCODE -ne 0) {
    Write-Warning 'sshd configuration validation failed. Restoring the previous configuration.'
    Copy-Item -LiteralPath $backupConfig -Destination $sshdConfig -Force
    throw 'Invalid sshd_config. The previous configuration was restored.'
}

Write-Host '[+] Enabling and restarting OpenSSH...'
Set-Service -Name sshd -StartupType Automatic
Restart-Service -Name sshd -Force

$firewall = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
if ($firewall) {
    if ($firewall.Enabled -ne 'True') {
        Enable-NetFirewallRule -Name 'OpenSSH-Server-In-TCP'
    }
}
else {
    $firewallParams = @{
        Name        = 'OpenSSH-Server-In-TCP'
        DisplayName = 'OpenSSH Server (TCP 22)'
        Direction   = 'Inbound'
        Protocol    = 'TCP'
        LocalPort   = 22
        Action      = 'Allow'
    }
    New-NetFirewallRule @firewallParams | Out-Null
}

Write-Host ''
Write-Host 'SFTP backup access configured successfully.' -ForegroundColor Green
Write-Host "User: $UserName"
if ($AllowFrom) {
    Write-Host "Allowed from: $AllowFrom"
}
Write-Host ''
Write-Host 'NTFS permissions were NOT changed by this script.'
Write-Host 'The existing user must already have read access to the paths that should be backed up.'
Write-Host 'No chroot is configured, so SFTP can address the Windows drives/paths allowed to this user.'
