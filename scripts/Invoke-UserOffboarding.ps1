<#
.SYNOPSIS
    Offboard one or more users: disable, record and remove groups, scramble password,
    stamp the description, move to the Disabled Users OU, and log everything.

.DESCRIPTION
    Order matters:
      1. Record group membership FIRST - if HR reverses the termination, or a manager
         needs to know what access the leaver had, the log is the only record.
      2. Disable - stops new sign-ins immediately.
      3. Scramble the password - protects against anyone who knew it.
      4. Remove groups - removes access to shares, apps and distribution lists.
         "Domain Users" stays because it is the primary group and cannot be removed.
      5. Description + move - anyone looking at the account can see when, why and
         under which ticket it was disabled. The Disabled Users OU has no GPOs linked
         and is easy to review for deletion after the retention period.

    We do NOT delete the account: deletion loses the SID, so file ownership and
    audit history become unreadable, and the account cannot be restored easily.

.EXAMPLE
    .\Invoke-UserOffboarding.ps1 -Identity liam.carter -Ticket RITM0010042 -WhatIf
    .\Invoke-UserOffboarding.ps1 -Identity liam.carter, harper.evans -Ticket RITM0010042
#>
#Requires -Modules ActiveDirectory
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory, ValueFromPipeline)] [string[]] $Identity,
    [Parameter(Mandatory)] [string] $Ticket,
    [string] $DisabledOU,
    [string] $LogPath = (Join-Path $PSScriptRoot 'logs\Offboarding.log')
)

begin {
    Import-Module ActiveDirectory
    $domain = Get-ADDomain
    if (-not $DisabledOU) { $DisabledOU = "OU=Disabled Users,OU=Corp,$($domain.DistinguishedName)" }
    New-Item -Path (Split-Path $LogPath) -ItemType Directory -Force -WhatIf:$false | Out-Null

    function Write-Log {
        param([string] $User, [string] $Action, [string] $Detail, [string] $Result = 'OK')
        $line = '{0}|{1}|{2}|{3}|{4}|{5}|{6}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),
            "$env:USERDOMAIN\$env:USERNAME", $Ticket, $User, $Action, $Result, $Detail
        Add-Content -Path $LogPath -Value $line -WhatIf:$false
        Write-Host $line -ForegroundColor ($(if ($Result -eq 'OK') { 'Gray' } else { 'Yellow' }))
    }

    if (-not (Test-Path $LogPath) -or (Get-Item $LogPath).Length -eq 0) {
        Add-Content -Path $LogPath -Value 'Timestamp|Operator|Ticket|User|Action|Result|Detail' -WhatIf:$false
    }
}

process {
    foreach ($id in $Identity) {
        try {
            $user = Get-ADUser -Identity $id -Properties MemberOf, Description, Enabled, ProtectedFromAccidentalDeletion -ErrorAction Stop
        } catch {
            Write-Log -User $id -Action 'Lookup' -Detail $_.Exception.Message -Result 'FAILED'
            continue
        }
        $sam = $user.SamAccountName

        # 1. Record current access
        $groupNames = foreach ($dn in $user.MemberOf) { (Get-ADGroup -Identity $dn).Name }
        Write-Log -User $sam -Action 'GroupsBefore' -Detail (($groupNames | Sort-Object) -join ';')

        if (-not $PSCmdlet.ShouldProcess($sam, "Offboard under $Ticket")) { continue }

        try {
            # 2. Disable
            Disable-ADAccount -Identity $user
            Write-Log -User $sam -Action 'Disable' -Detail 'Account disabled'

            # 3. Scramble password
            $chars = [char[]](33..126)
            $pw    = -join (1..32 | ForEach-Object { $chars | Get-Random })
            Set-ADAccountPassword -Identity $user -Reset -NewPassword (ConvertTo-SecureString $pw -AsPlainText -Force)
            Write-Log -User $sam -Action 'PasswordReset' -Detail 'Random 32-char password set'

            # 4. Remove groups (primary group Domain Users is not in MemberOf)
            foreach ($dn in $user.MemberOf) {
                Remove-ADGroupMember -Identity $dn -Members $user -Confirm:$false
                Write-Log -User $sam -Action 'RemoveGroup' -Detail (Get-ADGroup $dn).Name
            }

            # 5. Stamp description
            $stamp = "Disabled $(Get-Date -Format 'yyyy-MM-dd') by $env:USERNAME per $Ticket. Was: $($user.Description)"
            Set-ADUser -Identity $user -Description $stamp.Substring(0, [Math]::Min(1024, $stamp.Length))
            Write-Log -User $sam -Action 'Description' -Detail $stamp

            # 6. Move to Disabled Users
            if ($user.ProtectedFromAccidentalDeletion) {
                Set-ADObject -Identity $user -ProtectedFromAccidentalDeletion $false
            }
            Move-ADObject -Identity $user -TargetPath $DisabledOU
            Write-Log -User $sam -Action 'Move' -Detail $DisabledOU
        } catch {
            Write-Log -User $sam -Action 'Error' -Detail $_.Exception.Message -Result 'FAILED'
        }
    }
}

end {
    Write-Host "`nLog file: $LogPath" -ForegroundColor Green
}
