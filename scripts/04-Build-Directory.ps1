<#
.SYNOPSIS
    Phase 5: OU structure, security groups, delegation, service account and the file share.

.DESCRIPTION
    Run on DC01 as a Domain Admin. Safe to re-run: every object is created only if missing.

    Why OUs:     OUs are where you LINK Group Policy and DELEGATE admin rights.
                 Security groups are for PERMISSIONS. Don't mix the two ideas.
    Why groups:  permissions are always granted to groups, never to individual users,
                 so onboarding/offboarding is "add/remove group" - no ACL editing.
    Why delegation: Tier 1 needs to reset passwords and unlock accounts. Giving them
                 Domain Admin for that is how breaches happen. GS-IT-Support gets
                 exactly those rights on the Corp OU and nothing more.
    Share vs NTFS: when both apply (access over the network) the MOST restrictive wins.
                 Standard practice: share permission broad (Authenticated Users = Change),
                 NTFS does the real control. Access-based enumeration hides folders a user
                 cannot open.
#>
#Requires -RunAsAdministrator
#Requires -Modules ActiveDirectory
[CmdletBinding()]
param(
    [string] $ShareRoot = 'C:\Shares\Departments',
    [string] $ShareName = 'Departments'
)

$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory

$domain   = Get-ADDomain
$domainDN = $domain.DistinguishedName
$nb       = $domain.NetBIOSName

function New-LabOU {
    param([string] $Name, [string] $Path)
    $dn = "OU=$Name,$Path"
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$dn'" -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $Name -Path $Path -ProtectedFromAccidentalDeletion $true
        Write-Host "  + OU  $dn"
    }
    $dn
}

# ---------------------------------------------------------------- 1. OUs
Write-Host '[1/6] Organisational units' -ForegroundColor Cyan
$corp   = New-LabOU 'Corp'        $domainDN
$ho     = New-LabOU 'Head Office' $corp
$null   = New-LabOU 'Users'       $ho
$null   = New-LabOU 'Computers'   $ho
$stores = New-LabOU 'Stores'      $corp
foreach ($store in 'Store-0421', 'Store-0587') {
    $s    = New-LabOU $store $stores
    $null = New-LabOU 'Users'     $s
    $null = New-LabOU 'Computers' $s
}
$it     = New-LabOU 'IT'               $corp
$null   = New-LabOU 'Users'            $it
$null   = New-LabOU 'Admin Accounts'   $it
$groups = New-LabOU 'Groups'           $corp
$svc    = New-LabOU 'Service Accounts' $corp
$null   = New-LabOU 'Disabled Users'   $corp

# ---------------------------------------------------------------- 2. Groups
Write-Host '[2/6] Security groups' -ForegroundColor Cyan
$groupList = [ordered]@{
    'GS-Finance-RW'      = 'Modify access to \\DC01\Departments\Finance'
    'GS-Finance-RO'      = 'Read-only access to \\DC01\Departments\Finance'
    'GS-HR-RW'           = 'Modify access to \\DC01\Departments\HR'
    'GS-Merch-RW'        = 'Modify access to \\DC01\Departments\Merchandising'
    'GS-StoreOps-RW'     = 'Modify access to \\DC01\Departments\StoreOps'
    'GS-Store0421-Users' = 'All staff at Store 0421 (drive-map targeting)'
    'GS-Store0587-Users' = 'All staff at Store 0587 (drive-map targeting)'
    'GS-IT-Support'      = 'Tier 1/2 IT: delegated password reset and unlock on OU=Corp'
    'GS-IT-Admins'       = 'Privileged adm.* accounts; target of PSO-IT-Admins'
}
foreach ($g in $groupList.GetEnumerator()) {
    if (-not (Get-ADGroup -Filter "Name -eq '$($g.Key)'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name $g.Key -SamAccountName $g.Key -GroupScope Global -GroupCategory Security `
            -Path $groups -Description $g.Value
        Write-Host "  + Group $($g.Key)"
    }
}

# ---------------------------------------------------------------- 3. Delegation
# GUI: ADUC > right-click Corp OU > Delegate Control > GS-IT-Support >
#      "Reset user passwords and force password change at next logon" + custom lockoutTime.
Write-Host '[3/6] Delegating password reset / unlock to GS-IT-Support' -ForegroundColor Cyan
dsacls $corp /I:S /G "$nb\GS-IT-Support:CA;Reset Password;user"        | Out-Null
dsacls $corp /I:S /G "$nb\GS-IT-Support:RPWP;pwdLastSet;user"          | Out-Null
dsacls $corp /I:S /G "$nb\GS-IT-Support:RPWP;lockoutTime;user"         | Out-Null

# ---------------------------------------------------------------- 4. Service account
# Retail example: store MFPs use this account for scan-to-folder.
# In production prefer a gMSA where the application supports it.
Write-Host '[4/6] Service account' -ForegroundColor Cyan
if (-not (Get-ADUser -Filter "SamAccountName -eq 'svc-scan'" -ErrorAction SilentlyContinue)) {
    $chars = [char[]](33..126)
    $pw    = -join (1..32 | ForEach-Object { $chars | Get-Random })
    New-ADUser -Name 'svc-scan' -SamAccountName 'svc-scan' -UserPrincipalName "svc-scan@$($domain.DNSRoot)" `
        -Path $svc -Description 'Store MFP scan-to-folder. Owner: IT. Do not use interactively.' `
        -AccountPassword (ConvertTo-SecureString $pw -AsPlainText -Force) `
        -PasswordNeverExpires $true -CannotChangePassword $true -Enabled $true
    Write-Host '  + svc-scan created (random 32-char password, not stored anywhere).'
}

# ---------------------------------------------------------------- 5. Folders + NTFS
Write-Host '[5/6] Folders and NTFS permissions' -ForegroundColor Cyan
$folders = [ordered]@{
    'Finance'       = @("$nb\GS-Finance-RW:(OI)(CI)M", "$nb\GS-Finance-RO:(OI)(CI)RX")
    'HR'            = @("$nb\GS-HR-RW:(OI)(CI)M")
    'Merchandising' = @("$nb\GS-Merch-RW:(OI)(CI)M")
    'StoreOps'      = @("$nb\GS-StoreOps-RW:(OI)(CI)M", "$nb\GS-Store0421-Users:(OI)(CI)RX", "$nb\GS-Store0587-Users:(OI)(CI)RX")
    'Public'        = @("$nb\Domain Users:(OI)(CI)M")
    'IT'            = @("$nb\GS-IT-Support:(OI)(CI)M")
}

New-Item -Path $ShareRoot -ItemType Directory -Force | Out-Null

# Root: remove inherited entries, then grant:
#   SYSTEM / Administrators / GS-IT-Admins = Full, inherited by everything below
#   Domain Users = Read & execute on THIS FOLDER ONLY (no OI/CI) so they can open the
#   share and see the folder list, but get nothing inside unless a group grants it.
icacls $ShareRoot /inheritance:r /grant:r `
    'NT AUTHORITY\SYSTEM:(OI)(CI)F' 'BUILTIN\Administrators:(OI)(CI)F' `
    "$nb\GS-IT-Admins:(OI)(CI)F" "$nb\Domain Users:(RX)" | Out-Null

foreach ($f in $folders.GetEnumerator()) {
    $path = Join-Path $ShareRoot $f.Key
    New-Item -Path $path -ItemType Directory -Force | Out-Null
    foreach ($ace in $f.Value) { icacls $path /grant $ace | Out-Null }
    Write-Host "  + $path"
}

# ---------------------------------------------------------------- 6. SMB share
Write-Host '[6/6] SMB share' -ForegroundColor Cyan
if (-not (Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue)) {
    New-SmbShare -Name $ShareName -Path $ShareRoot -FolderEnumerationMode AccessBased `
        -FullAccess 'BUILTIN\Administrators' -ChangeAccess 'NT AUTHORITY\Authenticated Users' `
        -Description 'Department shares - access controlled by NTFS + GS-* groups' | Out-Null
}

Write-Host "`n--- Verification ---" -ForegroundColor Green
Get-ADOrganizationalUnit -SearchBase $corp -Filter * | Sort-Object DistinguishedName | Format-Table Name, DistinguishedName -AutoSize
Get-ADGroup -SearchBase $groups -Filter * | Format-Table Name, GroupScope, Description -AutoSize
Get-SmbShareAccess -Name $ShareName | Format-Table AccountName, AccessControlType, AccessRight
icacls (Join-Path $ShareRoot 'Finance')
