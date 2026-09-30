<#
.SYNOPSIS
    Phase 3: NAT routing, DNS zones and forwarders, DHCP scope and authorisation.

.DESCRIPTION
    Run on DC01 as CORP\Administrator after promotion.

    NAT (RRAS):  lets lab clients reach the internet through DC01's WAN NIC while
                 the lab network itself stays isolated. DHCP option 003 points
                 clients at DC01 (10.10.10.10) as their default gateway.
    DNS:         the forward zone corp.homelab.local was created by promotion.
                 We add a reverse zone (IP -> name, used by nslookup and many tools),
                 forwarders (how the DC resolves internet names), and scavenging
                 (removes stale records left by old DHCP clients).
    DHCP:        scope, exclusion, options 003/006/015, a reservation, and
                 authorisation in AD. An unauthorised Windows DHCP server on a
                 domain member refuses to lease addresses - a protection against
                 rogue DHCP servers.

.EXAMPLE
    .\03-Configure-NetworkServices.ps1 -WS01Mac '00-15-5D-01-02-03'
#>
#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]   $DomainName   = 'corp.homelab.local',
    [string]   $DcIP         = '10.10.10.10',
    [string]   $ScopeId      = '10.10.10.0',
    [string]   $ScopeStart   = '10.10.10.100',
    [string]   $ScopeEnd     = '10.10.10.200',
    [string]   $ExclStart    = '10.10.10.100',
    [string]   $ExclEnd      = '10.10.10.109',
    [string[]] $Forwarders   = @('1.1.1.1', '8.8.8.8'),
    [string]   $WS01Mac,                             # optional: MAC of WS01 for the reservation
    [string]   $WS01ReservedIP = '10.10.10.150',
    [switch]   $SkipNat
)

$ErrorActionPreference = 'Stop'
$fqdn = "$env:COMPUTERNAME.$DomainName".ToLower()

# ---------------------------------------------------------------- 1. NAT
if (-not $SkipNat) {
    Write-Host '[NAT] Installing Remote Access (routing)...' -ForegroundColor Cyan
    Install-WindowsFeature RemoteAccess, Routing -IncludeManagementTools | Out-Null
    Install-RemoteAccess -VpnType RoutingOnly -ErrorAction SilentlyContinue

    # GUI equivalent: Routing and Remote Access > IPv4 > NAT > New Interface
    netsh routing ip nat install
    netsh routing ip nat add interface name="WAN" mode=full
    netsh routing ip nat add interface name="LAB" mode=private
    Restart-Service RemoteAccess
}

# ---------------------------------------------------------------- 2. DNS
Write-Host '[DNS] Reverse zone, PTR record, forwarders, scavenging...' -ForegroundColor Cyan

if (-not (Get-DnsServerZone -Name '10.10.10.in-addr.arpa' -ErrorAction SilentlyContinue)) {
    # AD-integrated + Forest replication = stored in AD, replicated to every DNS server on a DC
    Add-DnsServerPrimaryZone -NetworkId '10.10.10.0/24' -ReplicationScope Forest -DynamicUpdate Secure
}

# PTR for the DC itself (clients register their own PTR via DHCP / dynamic update)
if (-not (Get-DnsServerResourceRecord -ZoneName '10.10.10.in-addr.arpa' -Name '10' -RRType Ptr -ErrorAction SilentlyContinue)) {
    Add-DnsServerResourceRecordPtr -ZoneName '10.10.10.in-addr.arpa' -Name '10' -PtrDomainName "$fqdn."
}

Set-DnsServerForwarder -IPAddress $Forwarders -UseRootHint $true

# Scavenging: records not refreshed for 7+7 days are removed.
Set-DnsServerScavenging -ScavengingState $true -ScavengingInterval 7.00:00:00 -ApplyOnAllZones
Set-DnsServerZoneAging -Name $DomainName -Aging $true
Set-DnsServerZoneAging -Name '10.10.10.in-addr.arpa' -Aging $true

# ---------------------------------------------------------------- 3. DHCP
Write-Host '[DHCP] Installing and configuring...' -ForegroundColor Cyan
Install-WindowsFeature DHCP -IncludeManagementTools | Out-Null

# Creates the local "DHCP Administrators" and "DHCP Users" groups
netsh dhcp add securitygroups
Restart-Service DHCPServer

# Authorise in AD (GUI: DHCP console > right-click server > Authorize)
if (-not (Get-DhcpServerInDC | Where-Object DnsName -eq $fqdn)) {
    Add-DhcpServerInDC -DnsName $fqdn -IPAddress $DcIP
}

# Tell Server Manager the post-install wizard is done (removes the yellow flag)
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager\Roles\12' -Name ConfigurationState -Value 2

if (-not (Get-DhcpServerv4Scope -ScopeId $ScopeId -ErrorAction SilentlyContinue)) {
    Add-DhcpServerv4Scope -Name 'LAB-Workstations' -StartRange $ScopeStart -EndRange $ScopeEnd `
        -SubnetMask 255.255.255.0 -LeaseDuration 8.00:00:00 -State Active
    Add-DhcpServerv4ExclusionRange -ScopeId $ScopeId -StartRange $ExclStart -EndRange $ExclEnd
}

# Scope options: 003 Router, 006 DNS Servers, 015 DNS Domain Name
Set-DhcpServerv4OptionValue -ScopeId $ScopeId -Router $DcIP -DnsServer $DcIP -DnsDomain $DomainName

if ($WS01Mac) {
    if (-not (Get-DhcpServerv4Reservation -ScopeId $ScopeId -ErrorAction SilentlyContinue |
              Where-Object IPAddress -eq $WS01ReservedIP)) {
        Add-DhcpServerv4Reservation -ScopeId $ScopeId -IPAddress $WS01ReservedIP -ClientId $WS01Mac `
            -Name "ws01.$DomainName" -Description 'Head Office workstation'
    }
} else {
    Write-Warning 'No -WS01Mac supplied. Build WS01 first, then re-run with its MAC (Get-NetAdapter on WS01).'
}

# ---------------------------------------------------------------- 4. Verify
Write-Host "`n--- Verification ---" -ForegroundColor Green
Resolve-DnsName -Name "_ldap._tcp.dc._msdcs.$DomainName" -Type SRV -Server $DcIP | Format-Table Name, NameTarget, Port
Resolve-DnsName -Name $DcIP -Server $DcIP | Format-Table Name, NameHost
Get-DnsServerForwarder | Format-List IPAddress
Get-DhcpServerInDC
Get-DhcpServerv4Scope | Format-Table ScopeId, Name, StartRange, EndRange, State, LeaseDuration
Get-DhcpServerv4OptionValue -ScopeId $ScopeId | Format-Table OptionId, Name, Value
