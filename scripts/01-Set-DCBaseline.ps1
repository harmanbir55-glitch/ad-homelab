<#
.SYNOPSIS
    Phase 2 baseline for the domain controller: NIC names, static IP, DNS, computer name.

.DESCRIPTION
    Run on the freshly installed Windows Server 2022 VM BEFORE installing AD DS.

    Why each step matters:
      * Static IP  - clients find the DC through DNS records that point at its IP.
                     If the DC's IP changed (DHCP), every client would break.
      * DNS -> self - after promotion the DC hosts the domain's DNS zone. A DC that
                     asks a public resolver for its own domain gets NXDOMAIN.
      * WAN NIC not registered in DNS - otherwise the DC registers its NAT address
                     (e.g. 192.168.x.x or 172.x.x.x) as a second A record, and clients
                     randomly try to reach the DC on an address they cannot route to.
      * Rename before promotion - renaming a DC after promotion is possible but
                     messy (netdom computername). Do it now.

.EXAMPLE
    Get-NetAdapter        # identify which adapter is on the lab network
    .\01-Set-DCBaseline.ps1 -LabAdapter 'Ethernet' -WanAdapter 'Ethernet 2'
#>
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string] $LabAdapter,   # NIC on the isolated lab network
    [Parameter(Mandatory)] [string] $WanAdapter,   # NIC on the hypervisor NAT network
    [string] $IPAddress   = '10.10.10.10',
    [int]    $PrefixLength = 24,
    [string] $NewName     = 'DC01'
)

$ErrorActionPreference = 'Stop'

# 1. Friendly adapter names make every later command and screenshot readable.
Rename-NetAdapter -Name $LabAdapter -NewName 'LAB'
Rename-NetAdapter -Name $WanAdapter -NewName 'WAN'

# 2. Static IP on the lab NIC. No default gateway here: the WAN NIC gets its gateway
#    from the hypervisor's DHCP. Two default gateways on one host causes routing chaos.
Set-NetIPInterface -InterfaceAlias 'LAB' -Dhcp Disabled
Get-NetIPAddress -InterfaceAlias 'LAB' -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Remove-NetIPAddress -Confirm:$false
New-NetIPAddress -InterfaceAlias 'LAB' -IPAddress $IPAddress -PrefixLength $PrefixLength | Out-Null

# 3. DNS: own IP first, loopback second (Microsoft best practice for a single DC).
Set-DnsClientServerAddress -InterfaceAlias 'LAB' -ServerAddresses $IPAddress, '127.0.0.1'
Set-DnsClientServerAddress -InterfaceAlias 'WAN' -ServerAddresses $IPAddress

# 4. Only the LAB address should ever appear in the domain's DNS.
Set-DnsClient -InterfaceAlias 'WAN' -RegisterThisConnectionsAddress $false

# 5. Show the result so you can screenshot it.
Get-NetIPConfiguration -InterfaceAlias 'LAB', 'WAN' | Format-List InterfaceAlias, IPv4Address, IPv4DefaultGateway, DNSServer

# 6. Rename and reboot.
if ($env:COMPUTERNAME -ne $NewName) {
    Write-Host "Renaming $env:COMPUTERNAME to $NewName and restarting..." -ForegroundColor Yellow
    Rename-Computer -NewName $NewName -Restart
}
