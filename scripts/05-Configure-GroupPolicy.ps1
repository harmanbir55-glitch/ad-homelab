<#
.SYNOPSIS
    Phase 6: password policies, GPO creation/linking/settings, and GPO backups.

.DESCRIPTION
    Password policy for the domain:
      Set this in the GUI (GPMC > Default Domain Policy > Computer Configuration >
      Policies > Windows Settings > Security Settings > Account Policies).
      Do NOT rely on Set-ADDefaultDomainPasswordPolicy alone: it writes to the domain
      object directly, and the next time the DC re-applies the Default Domain Policy
      those values can be overwritten by whatever the GPO says. This script only
      VERIFIES the result.

    Fine-grained password policy (PSO):
      A stricter policy for privileged accounts. PSOs apply to users or global groups,
      never to OUs, and override the domain policy for those users.

    GPOs:
      U-*  = user settings only (computer half disabled)
      C-*  = computer settings only (user half disabled)
      Group Policy Preferences drive maps and WMI filters are configured in the GUI
      (see docs/build-guide.md, Phase 6) - there are no native cmdlets for them.
#>
#Requires -RunAsAdministrator
#Requires -Modules ActiveDirectory, GroupPolicy
[CmdletBinding()]
param(
    [string] $WallpaperFile = 'store-wallpaper.jpg',   # place this file in NETLOGON first
    [string] $BackupPath    = 'C:\GPOBackups'
)

$ErrorActionPreference = 'Stop'
$domain  = Get-ADDomain
$dnsRoot = $domain.DNSRoot
$corp    = "OU=Corp,$($domain.DistinguishedName)"
$stores  = "OU=Stores,$corp"

# ---------------------------------------------------------------- 1. Verify domain policy
Write-Host '[1/5] Current domain password policy (set via Default Domain Policy GPO)' -ForegroundColor Cyan
Get-ADDefaultDomainPasswordPolicy |
    Format-List MinPasswordLength, PasswordHistoryCount, MaxPasswordAge, MinPasswordAge,
                ComplexityEnabled, LockoutThreshold, LockoutDuration, LockoutObservationWindow

# ---------------------------------------------------------------- 2. Fine-grained policy
Write-Host '[2/5] Fine-grained password policy for GS-IT-Admins' -ForegroundColor Cyan
if (-not (Get-ADFineGrainedPasswordPolicy -Filter "Name -eq 'PSO-IT-Admins'")) {
    New-ADFineGrainedPasswordPolicy -Name 'PSO-IT-Admins' -Precedence 10 `
        -MinPasswordLength 15 -PasswordHistoryCount 24 -ComplexityEnabled $true `
        -ReversibleEncryptionEnabled $false -MaxPasswordAge 60.00:00:00 -MinPasswordAge 1.00:00:00 `
        -LockoutThreshold 3 -LockoutDuration 00:30:00 -LockoutObservationWindow 00:30:00 `
        -Description 'Stricter policy for privileged adm.* accounts'
}
Add-ADFineGrainedPasswordPolicySubject -Identity 'PSO-IT-Admins' -Subjects 'GS-IT-Admins'

# ---------------------------------------------------------------- helper
function New-LabGPO {
    param([string] $Name, [string] $Comment, [string] $Target, [ValidateSet('User','Computer')] [string] $Scope)
    $gpo = Get-GPO -Name $Name -ErrorAction SilentlyContinue
    if (-not $gpo) {
        $gpo = New-GPO -Name $Name -Comment $Comment
        Write-Host "  + GPO $Name"
    }
    # Disable the unused half: faster processing, and no accidental cross-half settings.
    $gpo.GpoStatus = if ($Scope -eq 'User') { 'ComputerSettingsDisabled' } else { 'UserSettingsDisabled' }
    $linked = (Get-GPInheritance -Target $Target).GpoLinks | Where-Object DisplayName -eq $Name
    if (-not $linked) { New-GPLink -Name $Name -Target $Target -LinkEnabled Yes | Out-Null }
    $gpo
}

# ---------------------------------------------------------------- 3. GPOs
Write-Host '[3/5] Creating and linking GPOs' -ForegroundColor Cyan

# 3a. Store desktop lockdown (user settings, linked to Stores OU -> applies to store USERS)
$null = New-LabGPO -Name 'U-Stores-Desktop-Lockdown' -Scope User -Target $stores `
    -Comment 'Store users: no Control Panel/Settings, corporate wallpaper'
# User Configuration > Policies > Admin Templates > Control Panel > Prohibit access to Control Panel and PC settings
Set-GPRegistryValue -Name 'U-Stores-Desktop-Lockdown' -Key 'HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' `
    -ValueName 'NoControlPanel' -Type DWord -Value 1 | Out-Null
# User Configuration > Policies > Admin Templates > Desktop > Desktop > Desktop Wallpaper
Set-GPRegistryValue -Name 'U-Stores-Desktop-Lockdown' -Key 'HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System' `
    -ValueName 'Wallpaper' -Type String -Value "\\$dnsRoot\NETLOGON\$WallpaperFile" | Out-Null
Set-GPRegistryValue -Name 'U-Stores-Desktop-Lockdown' -Key 'HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System' `
    -ValueName 'WallpaperStyle' -Type String -Value '4' | Out-Null   # 4 = Fill

# 3b. Removable storage (computer settings, linked to Stores OU -> applies to store COMPUTERS)
$null = New-LabGPO -Name 'C-Stores-Removable-Storage' -Scope Computer -Target $stores `
    -Comment 'Store PCs: deny all removable storage (data-loss prevention)'
# Computer Configuration > Policies > Admin Templates > System > Removable Storage Access > All Removable Storage classes: Deny all access
Set-GPRegistryValue -Name 'C-Stores-Removable-Storage' -Key 'HKLM\Software\Policies\Microsoft\Windows\RemovableStorageDevices' `
    -ValueName 'Deny_All' -Type DWord -Value 1 | Out-Null

# 3c. Drive mappings (settings added in GPMC: User Config > Preferences > Windows Settings > Drive Maps)
$null = New-LabGPO -Name 'U-Drive-Mappings' -Scope User -Target $corp `
    -Comment 'GPP drive maps with item-level targeting by GS-* group'

# ---------------------------------------------------------------- 4. Report
Write-Host '[4/5] Link report' -ForegroundColor Cyan
foreach ($t in $corp, $stores) {
    "`n$t"
    (Get-GPInheritance -Target $t).InheritedGpoLinks | Format-Table Order, DisplayName, Enabled, Enforced, Target -AutoSize
}
Get-ADUserResultantPasswordPolicy -Identity 'adm.emily.chen' -ErrorAction SilentlyContinue |
    Format-List Name, MinPasswordLength, LockoutThreshold

# ---------------------------------------------------------------- 5. Backup
Write-Host "[5/5] Backing up all GPOs to $BackupPath (copy into the repo's /gpo-backups)" -ForegroundColor Cyan
New-Item -Path $BackupPath -ItemType Directory -Force | Out-Null
Backup-GPO -All -Path $BackupPath | Format-Table DisplayName, Id, CreationTime -AutoSize
Get-GPOReport -All -ReportType Html -Path (Join-Path $BackupPath 'All-GPOs-Report.html')
