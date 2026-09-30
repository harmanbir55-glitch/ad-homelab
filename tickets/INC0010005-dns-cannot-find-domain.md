# INC0010005 – Workstation cannot contact the domain; internet works

| Field | Value |
|---|---|
| Number | INC0010005 |
| Caller | Grace Nguyen (grace.nguyen) – Merchandise Planner, Head Office |
| Category / Subcategory | Network / DNS |
| Configuration Item | WS01 |
| Contact type | Phone |
| Impact | 3 – Low (single workstation) |
| Urgency | 1 – High (no access to shared drives or apps) |
| Priority | **P3 – Moderate** |
| Assignment group | Service Desk – Tier 1 |
| Assigned to | Arjun Mehta |
| State | Resolved |
| Linked KB | [KB0010005 – Can't reach company network](../kb/KB0010005-cannot-reach-company-network.md) |

## Short description
WS01: shared drives and domain resources unavailable, websites load fine.

## Description (as reported by the user)
> "Websites work but my M: drive has a red X and it says the network path can't be found. It was fine on Friday. A vendor was on my PC Friday afternoon fixing the label printer."

## Work notes

| Time | Note |
|---|---|
| 2026-10-12 08:55 | Call received. Identity verified (employee ID + callback). User signed in with cached credentials. |
| 08:57 | Remote session to WS01. `ipconfig /all` → IPv4 10.10.10.150 (DHCP reservation, correct), gateway 10.10.10.10, **DNS Servers: 8.8.8.8**. Expected 10.10.10.10 from DHCP option 006. A manually set DNS server overrides DHCP. |
| 08:58 | `nltest /dsgetdc:corp.homelab.local` → **`ERROR_NO_SUCH_DOMAIN` (1355)**. Client cannot locate a domain controller. |
| 08:59 | `nslookup corp.homelab.local` → server `dns.google`, **Non-existent domain**. `Resolve-DnsName _ldap._tcp.dc._msdcs.corp.homelab.local -Type SRV` → DNS name does not exist. Public DNS has no knowledge of our internal zone. |
| 09:00 | `Test-NetConnection 10.10.10.10 -Port 445` → TcpTestSucceeded True. Network path is fine; this is purely name resolution. |
| 09:01 | Fix (elevated, via remote support tool): `Set-DnsClientServerAddress -InterfaceAlias Ethernet -ResetServerAddresses` (back to "Obtain DNS server address automatically"), `ipconfig /flushdns`, `ipconfig /registerdns`. |
| 09:02 | `ipconfig /all` → DNS 10.10.10.10. `nltest /dsgetdc:corp.homelab.local` → `DC: \\DC01.corp.homelab.local`, flags GC DS LDAP KDC. `Resolve-DnsName dc01.corp.homelab.local` → 10.10.10.10. |
| 09:04 | `gpupdate /force` succeeded. M: and P: reconnect. User confirmed. Label printer tested with the user – still prints (it's USB-connected, DNS change was not needed). |
| 09:05 | Resolving. Informed Desktop Support lead about third-party vendor making network changes. |

## Root cause
A vendor manually set the network adapter's DNS server to 8.8.8.8 while troubleshooting a printer. Domain members must use AD-integrated DNS (the DC) to find domain controllers via SRV records; public DNS has no record of corp.homelab.local, so every domain lookup failed while internet names still resolved.

## Resolution
Reset the adapter's DNS to DHCP-assigned (DC01, 10.10.10.10), flushed and re-registered DNS, verified DC discovery with nltest and SRV lookups.

## Resolution code
Solved Remotely

## Tier 1 resolvable?
**Yes**, with the remote support tool's elevated session. Without admin rights, escalate to Desktop Support:

> WS01 has static DNS 8.8.8.8 (set by vendor Fri). nltest /dsgetdc returns 1355, SRV lookup fails, TCP 445 to DC01 OK. Please reset DNS to automatic. User on cached credentials, no share access. P3.

## Key point
**"Internet works but domain doesn't" is almost always DNS.** Public DNS can resolve google.com but will never know about an internal AD domain. Clients, servers and even DCs should point only at internal DNS servers; the DCs forward internet queries.

## How this scenario was reproduced in the lab
On WS01: `Set-DnsClientServerAddress -InterfaceAlias Ethernet -ServerAddresses 8.8.8.8`, `ipconfig /flushdns`, then signed in as grace.nguyen.
