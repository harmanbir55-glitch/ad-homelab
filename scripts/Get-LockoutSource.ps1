<#
.SYNOPSIS
    Find where an account's lockouts come from, and show its lockout state on every DC.

.DESCRIPTION
    How lockouts work:
      * Every failed logon is checked against the PDC emulator, so the PDC emulator's
        Security log always has Event ID 4740 ("A user account was locked out").
        The "Caller Computer Name" field in 4740 is the machine that sent the bad password.
      * badPwdCount is NOT replicated between DCs, so it is queried on each DC.
      * If Caller Computer Name is blank, the source is often a non-Windows device
        (phone mail app, Wi-Fi/RADIUS) - check Event 4771/4625 and NPS logs.

    Requires "Audit User Account Management" (Success) on DCs - on by default on
    Server 2016+. Check with:  auditpol /get /subcategory:"User Account Management"

    This replaces the legacy LockoutStatus.exe (Account Lockout and Management Tools).

.EXAMPLE
    .\Get-LockoutSource.ps1 -Identity jacob.wilson
    .\Get-LockoutSource.ps1 -Identity jacob.wilson -Hours 72 -Unlock
#>
#Requires -Modules ActiveDirectory
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Identity,
    [int] $Hours = 24,
    [switch] $Unlock
)

Import-Module ActiveDirectory
$pdc = (Get-ADDomain).PDCEmulator

Write-Host "`n=== Lockout state per DC ===" -ForegroundColor Cyan
$state = foreach ($dc in Get-ADDomainController -Filter *) {
    $u = Get-ADUser -Identity $Identity -Server $dc.HostName `
        -Properties LockedOut, badPwdCount, LastBadPasswordAttempt, AccountLockoutTime, PasswordLastSet
    [pscustomobject]@{
        DC                     = $dc.HostName
        User                   = $u.SamAccountName
        LockedOut              = $u.LockedOut
        BadPwdCount            = $u.badPwdCount
        LastBadPasswordAttempt = $u.LastBadPasswordAttempt
        AccountLockoutTime     = $u.AccountLockoutTime
        PasswordLastSet        = $u.PasswordLastSet
    }
}
$state | Format-Table -AutoSize

Write-Host "=== Event 4740 on PDC emulator $pdc (last $Hours h) ===" -ForegroundColor Cyan
$sam = (Get-ADUser -Identity $Identity).SamAccountName
try {
    $events = Get-WinEvent -ComputerName $pdc -FilterHashtable @{
        LogName = 'Security'; Id = 4740; StartTime = (Get-Date).AddHours(-$Hours)
    } -ErrorAction Stop | Where-Object { $_.Properties[0].Value -eq $sam }
} catch {
    $events = @()
    Write-Warning "No 4740 events found (or no access to the Security log): $($_.Exception.Message)"
}

if ($events) {
    $events | Select-Object TimeCreated,
        @{n='User';           e={ $_.Properties[0].Value }},
        @{n='CallerComputer'; e={ if ($_.Properties[1].Value) { $_.Properties[1].Value } else { '(blank - check phones / RADIUS / 4771)' } }} |
        Format-Table -AutoSize

    Write-Host 'Lockouts per source:' -ForegroundColor Cyan
    $events | Group-Object { $_.Properties[1].Value } | Sort-Object Count -Descending |
        Format-Table @{n='CallerComputer';e={$_.Name}}, Count -AutoSize
}

if ($Unlock) {
    Unlock-ADAccount -Identity $Identity -Server $pdc
    Write-Host "$Identity unlocked on $pdc (replicates to other DCs)." -ForegroundColor Green
}
