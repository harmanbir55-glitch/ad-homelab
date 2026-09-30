<#
.SYNOPSIS
    Phase 2: install AD DS and promote DC01 as the first DC of a new forest.

.DESCRIPTION
    Why these settings:
      * corp.homelab.local - '.local' is fine for an isolated lab. In production,
        Microsoft recommends a subdomain of a domain you own (e.g. corp.contoso.com).
        For the optional Entra Cloud Sync phase we add a routable UPN suffix instead.
      * Functional level WinThreshold (2016) - the highest level Server 2022 offers.
      * -InstallDns - the new forest needs AD-integrated DNS; clients locate DCs
        through SRV records such as _ldap._tcp.dc._msdcs.corp.homelab.local.
      * DSRM password - the "break glass" local password used to boot the DC into
        Directory Services Restore Mode. Store it in a password manager.

    The server reboots automatically. Afterwards you log on as CORP\Administrator.

.EXAMPLE
    .\02-Install-ADDSForest.ps1
#>
#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string] $DomainName    = 'corp.homelab.local',
    [string] $NetBiosName   = 'CORP',
    [string] $FunctionalLevel = 'WinThreshold'
)

$ErrorActionPreference = 'Stop'

if ($env:COMPUTERNAME -ne 'DC01') {
    throw "Computer is still named $env:COMPUTERNAME. Run 01-Set-DCBaseline.ps1 first."
}

Write-Host 'Installing the AD DS role and management tools...' -ForegroundColor Cyan
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools | Out-Null

Import-Module ADDSDeployment
$dsrm = Read-Host -Prompt 'Enter a DSRM (Directory Services Restore Mode) password' -AsSecureString

$params = @{
    DomainName                    = $DomainName
    DomainNetbiosName             = $NetBiosName
    ForestMode                    = $FunctionalLevel
    DomainMode                    = $FunctionalLevel
    InstallDns                    = $true
    SafeModeAdministratorPassword = $dsrm
    DatabasePath                  = 'C:\Windows\NTDS'
    LogPath                       = 'C:\Windows\NTDS'
    SysvolPath                    = 'C:\Windows\SYSVOL'
}

# Pre-flight check: the same prerequisite tests the Server Manager wizard runs.
Write-Host 'Running prerequisite checks...' -ForegroundColor Cyan
$test = Test-ADDSForestInstallation @params -Force
$test | Format-Table Status, Message -Wrap
if ($test.Status -contains 'Error') { throw 'Prerequisite check failed. Fix the errors above.' }

# A warning about DNS delegation is expected for a new forest with no parent zone.
Write-Host 'Promoting to domain controller. The server will restart.' -ForegroundColor Yellow
Install-ADDSForest @params -Force
