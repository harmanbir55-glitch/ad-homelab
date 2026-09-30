# INC0010006 – Store 0421 devices have no network (169.254.x.x addresses)

| Field | Value |
|---|---|
| Number | INC0010006 |
| Caller | Olivia Martin (olivia.martin) – Store Manager, Store 0421 |
| Category / Subcategory | Network / DHCP |
| Configuration Item | DC01 – DHCP Server service; scope 10.10.10.0/24 |
| Contact type | Phone |
| Impact | 1 – High (whole site) |
| Urgency | 1 – High (devices cannot connect; revenue at risk) |
| Priority | **P1 – Critical** |
| Assignment group | Service Desk – Tier 1 → Windows Server Team |
| Assigned to | Arjun Mehta → Emily Chen |
| State | Resolved |
| Linked KB | [KB0010006 – No network / 169.254 address](../kb/KB0010006-no-network-169-address.md) |

## Short description
Store 0421: devices restarted this morning show "No internet", APIPA addresses.

## Description (as reported by the user)
> "The back-office PC and two registers we restarted this morning all say 'No internet'. The ones we didn't restart are still working. We open in 30 minutes."

## Work notes

| Time | Note |
|---|---|
| 2026-10-13 06:30 | Call received. Multiple devices at one site → treated as site-impacting. Priority P1 (Impact 1 × Urgency 1). Major incident process started, Service Desk lead notified. |
| 06:32 | Remote to WS02 (still reachable via console only). `ipconfig /all` → **IPv4 169.254.37.12**, subnet 255.255.0.0, no default gateway, DHCP Enabled Yes. 169.254.x.x = APIPA: Windows gives itself this when **no DHCP server answers**. |
| 06:33 | `ipconfig /release` then `ipconfig /renew` → "An error occurred while renewing interface Ethernet: **unable to contact your DHCP server**. Request has timed out." |
| 06:34 | Pattern explained: devices not restarted still hold a valid 8-day lease, so they keep working; only devices that requested a new lease fail. Points at the DHCP server, not cabling. |
| 06:35 | Escalated to Windows Server Team by phone + ticket (note below). |
| 06:41 | (Emily Chen) On DC01: `Get-Service DHCPServer` → **Stopped**, StartType **Manual**. System log Event 7036/7040: service start type changed and service stopped during overnight maintenance. |
| 06:42 | `Get-DhcpServerInDC` → DC01 authorised. `Get-DhcpServerv4ScopeStatistics` → (service stopped, n/a). |
| 06:43 | `Set-Service DHCPServer -StartupType Automatic`, `Start-Service DHCPServer`. `Get-DhcpServerv4ScopeStatistics` → 3% in use, 91 free. Scope healthy, not exhausted. |
| 06:44 | WS02: `ipconfig /renew` → 10.10.10.110, gateway 10.10.10.10, DNS 10.10.10.10. `nltest /dsgetdc:corp.homelab.local` OK. |
| 06:47 | Store confirmed all restarted devices online. Store opened on time. |
| 07:30 | Monitoring 45 min, no recurrence. Resolved. Problem record PRB0010003 raised: why the maintenance change set the service to Manual. |

## Root cause
The DHCP Server service on DC01 was stopped and its start type changed to Manual during overnight maintenance. Devices that restarted could not obtain a lease and fell back to APIPA (169.254.x.x) addresses, which cannot reach the gateway, DNS or DC.

## Resolution
Set the DHCP Server service to Automatic and started it; confirmed the scope had free addresses; renewed client leases and verified domain connectivity.

## Resolution code
Solved (Work Around) – service restored; underlying change-process cause tracked in PRB0010003.

## Tier 1 resolvable?
**No – Tier 1 identifies and escalates immediately** (P1, server-side). Escalation note:

> P1 – Store 0421. Restarted devices get 169.254.x.x (APIPA); ipconfig /renew "unable to contact your DHCP server". Devices with existing leases still working. Suspect DHCP service on DC01 or scope. Store opens 07:00. Store manager on 555-0421.

## Variant: scope exhausted
Same user symptom (APIPA), but the service is running.

| Check | Result when exhausted |
|---|---|
| `Get-DhcpServerv4ScopeStatistics` | `PercentageInUse 100`, `Free 0` |
| DHCP console → Address Leases | Every address in use, often by old or guest devices |
| Event log (Microsoft-Windows-DHCP-Server) | Event 1020 (scope nearly full), 1063 (no addresses available) |
| Fix | Delete stale leases, shorten lease duration for guest/device scopes, extend the range if the subnet allows, or add a scope |

Reproduce: leave only one address free and give it to a fake device, then renew WS02.

```powershell
# On DC01
Add-DhcpServerv4ExclusionRange -ScopeId 10.10.10.0 -StartRange 10.10.10.111 -EndRange 10.10.10.149
Add-DhcpServerv4ExclusionRange -ScopeId 10.10.10.0 -StartRange 10.10.10.151 -EndRange 10.10.10.200
Get-DhcpServerv4Lease -ScopeId 10.10.10.0 | Where-Object IPAddress -eq 10.10.10.110 | Remove-DhcpServerv4Lease
Add-DhcpServerv4Reservation -ScopeId 10.10.10.0 -IPAddress 10.10.10.110 -ClientId 00-11-22-33-44-55 -Name fake-device
# On WS02
ipconfig /release; ipconfig /renew     # -> APIPA
# Undo: remove the fake reservation and both exclusion ranges
```

## How this scenario was reproduced in the lab
On DC01: `Set-Service DHCPServer -StartupType Manual; Stop-Service DHCPServer`. On WS02: `ipconfig /release; ipconfig /renew`.
