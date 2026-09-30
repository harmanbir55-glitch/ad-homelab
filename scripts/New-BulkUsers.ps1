<#
.SYNOPSIS
    Bulk-onboard users from a CSV: correct OU, groups, temporary password, must change at next logon.

.DESCRIPTION
    CSV columns: FirstName, LastName, SamAccountName, Department, Title, Office,
                 EmployeeID, OUPath, Groups
      OUPath  - relative to the domain, e.g. "OU=Users,OU=Head Office,OU=Corp"
      Groups  - semicolon-separated, e.g. "GS-Store0421-Users;GS-StoreOps-RW"

    What it does for each row:
      1. Validates the row (required fields, OU exists, sAMAccountName <= 20 chars)
      2. Skips users that already exist (safe to re-run)
      3. Creates the user with UPN sam@domain, display name, department, title, office
      4. Sets the temporary password and "User must change password at next logon"
      5. Adds the user to each group (warns on groups that don't exist)
      6. Writes a line to the log file

    Why a temporary password + change at next logon: IT should never know a user's
    real password. The temp password is communicated through a verified channel and
    is useless as soon as the user signs in.

.PARAMETER CsvPath
    Path to the CSV file.
.PARAMETER LogPath
    Log file. Defaults to .\logs\Onboarding-<date>.log
.EXAMPLE
    .\New-BulkUsers.ps1 -CsvPath .\users.csv -WhatIf     # dry run: shows what would happen
    .\New-BulkUsers.ps1 -CsvPath .\users.csv             # prompts once for the temp password
#>
#Requires -Modules ActiveDirectory
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [ValidateScript({ Test-Path $_ })] [string] $CsvPath,
    [SecureString] $TempPassword,
    [string] $LogPath = (Join-Path $PSScriptRoot "logs\Onboarding-$(Get-Date -Format 'yyyyMMdd-HHmmss').log")
)

Import-Module ActiveDirectory
$domain   = Get-ADDomain
$domainDN = $domain.DistinguishedName
$upnSuffix = $domain.DNSRoot

New-Item -Path (Split-Path $LogPath) -ItemType Directory -Force -WhatIf:$false | Out-Null
function Write-Log {
    param([string] $Message, [ValidateSet('INFO','WARN','ERROR')] [string] $Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -Path $LogPath -Value $line -WhatIf:$false
    $color = @{ INFO = 'Gray'; WARN = 'Yellow'; ERROR = 'Red' }[$Level]
    Write-Host $line -ForegroundColor $color
}

if (-not $TempPassword -and -not $WhatIfPreference) {
    $TempPassword = Read-Host -Prompt 'Temporary password for new users (must meet domain policy)' -AsSecureString
}

$rows = Import-Csv -Path $CsvPath
$summary = [ordered]@{ Created = 0; Skipped = 0; Failed = 0 }
Write-Log "Onboarding started by $env:USERDOMAIN\$env:USERNAME. Rows: $($rows.Count). CSV: $CsvPath"

foreach ($r in $rows) {
    $sam = $r.SamAccountName.Trim().ToLower()

    # ---- Validate
    $missing = 'FirstName','LastName','SamAccountName','OUPath' | Where-Object { [string]::IsNullOrWhiteSpace($r.$_) }
    if ($missing) { Write-Log "Row for '$sam' missing: $($missing -join ', ')" ERROR; $summary.Failed++; continue }
    if ($sam.Length -gt 20) { Write-Log "$sam is longer than 20 characters (sAMAccountName limit)" ERROR; $summary.Failed++; continue }

    $ouDN = "$($r.OUPath),$domainDN"
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ouDN'" -ErrorAction SilentlyContinue)) {
        Write-Log "$sam - OU not found: $ouDN" ERROR; $summary.Failed++; continue
    }

    if (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
        Write-Log "$sam already exists - skipped" WARN; $summary.Skipped++; continue
    }

    # ---- Create
    $display = "$($r.FirstName) $($r.LastName)"
    $newUser = @{
        Name                  = $display
        GivenName             = $r.FirstName
        Surname               = $r.LastName
        DisplayName           = $display
        SamAccountName        = $sam
        UserPrincipalName     = "$sam@$upnSuffix"
        Department            = $r.Department
        Title                 = $r.Title
        Office                = $r.Office
        EmployeeID            = $r.EmployeeID
        Company               = 'NorthPeak Home Supply'
        Path                  = $ouDN
        AccountPassword       = $TempPassword
        ChangePasswordAtLogon = $true
        Enabled               = $true
    }

    if ($PSCmdlet.ShouldProcess("$sam in $ouDN", 'Create user')) {
        try {
            New-ADUser @newUser -ErrorAction Stop
            Write-Log "Created $sam ($display) in $ouDN"
            $summary.Created++
        } catch {
            Write-Log "Failed to create ${sam}: $($_.Exception.Message)" ERROR
            $summary.Failed++
            continue
        }
    }

    # ---- Groups
    $groupNames = ($r.Groups -split ';') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    foreach ($g in $groupNames) {
        if (-not (Get-ADGroup -Filter "Name -eq '$g'" -ErrorAction SilentlyContinue)) {
            Write-Log "$sam - group '$g' does not exist, not added" WARN
            continue
        }
        if ($PSCmdlet.ShouldProcess("$sam -> $g", 'Add to group')) {
            try {
                Add-ADGroupMember -Identity $g -Members $sam -ErrorAction Stop
                Write-Log "$sam added to $g"
            } catch {
                Write-Log "$sam could not be added to ${g}: $($_.Exception.Message)" ERROR
            }
        }
    }
}

Write-Log ("Onboarding finished. Created: {0}  Skipped: {1}  Failed: {2}" -f $summary.Created, $summary.Skipped, $summary.Failed)
Write-Host "`nLog file: $LogPath" -ForegroundColor Green
