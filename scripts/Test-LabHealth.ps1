<#
.SYNOPSIS
    One-screen health check for the lab DC. Run it after every build phase and after
    every break/fix scenario to prove the environment is back to a known-good state.
#>
#Requires -Modules ActiveDirectory
[CmdletBinding()]
param([string] $DomainName = (Get-ADDomain).DNSRoot)

function Show-Check([string] $Name, [bool] $Ok, [string] $Detail) {
    $mark = if ($Ok) { '[ OK ]' } else { '[FAIL]' }
    $col  = if ($Ok) { 'Green' } else { 'Red' }
    Write-Host ('{0} {1,-38} {2}' -f $mark, $Name, $Detail) -ForegroundColor $col
}

Write-Host "`nLab health check - $env:COMPUTERNAME - $(Get-Date)`n" -ForegroundColor Cyan

# Core services
foreach ($svc in 'NTDS', 'DNS', 'Netlogon', 'KDC', 'W32Time', 'DHCPServer', 'DFSR') {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    Show-Check "Service $svc" ($s.Status -eq 'Running') ($(if ($s) { "$($s.Status) / $($s.StartType)" } else { 'not installed' }))
}

# SYSVOL / NETLOGON shared (DC is advertising)
$shares = Get-SmbShare | Select-Object -ExpandProperty Name
Show-Check 'SYSVOL and NETLOGON shared' (($shares -contains 'SYSVOL') -and ($shares -contains 'NETLOGON')) ''

# DNS SRV record clients use to find a DC
$srv = Resolve-DnsName "_ldap._tcp.dc._msdcs.$DomainName" -Type SRV -ErrorAction SilentlyContinue
Show-Check 'DC locator SRV record' ([bool]$srv) (($srv | Where-Object Type -eq 'SRV').NameTarget -join ', ')

# External resolution through forwarders
$ext = Resolve-DnsName 'www.microsoft.com' -ErrorAction SilentlyContinue
Show-Check 'Internet name resolution' ([bool]$ext) ''

# DHCP authorisation and scope usage
if (Get-Command Get-DhcpServerInDC -ErrorAction SilentlyContinue) {
    $auth = Get-DhcpServerInDC | Where-Object { $_.DnsName -like "$env:COMPUTERNAME*" }
    Show-Check 'DHCP authorised in AD' ([bool]$auth) ''
    Get-DhcpServerv4ScopeStatistics -ErrorAction SilentlyContinue | ForEach-Object {
        Show-Check "Scope $($_.ScopeId) usage" ($_.PercentageInUse -lt 80) ("{0:N0}% in use, {1} free" -f $_.PercentageInUse, $_.Free)
    }
}

# Time source (the PDC emulator is the domain's time authority)
$src = (w32tm /query /source) -join ''
Show-Check 'Time source' ($src -notmatch 'Local CMOS Clock|Free-running') $src.Trim()

# dcdiag summary
Write-Host "`nRunning dcdiag /q (only failures are printed)..." -ForegroundColor Cyan
$diag = dcdiag /q
if ($diag) { $diag } else { Show-Check 'dcdiag' $true 'no failures reported' }
