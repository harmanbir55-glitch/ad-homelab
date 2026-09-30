# KB0010006 – "No internet" and a 169.254 address on a store or office computer

| | |
|---|---|
| **Article** | KB0010006 |
| **Audience** | All employees, store managers |
| **Applies to** | Wired and wireless company computers and registers |
| **Related incident** | [INC0010006](../tickets/INC0010006-dhcp-apipa-outage.md) |
| **Last reviewed** | 2026-10 |

## What you'll see
- The network icon shows a globe with "No internet" or "Unidentified network".
- Several devices at the same store lose connection — often **the ones that were just restarted** while others keep working.

## Why this happens
When a device connects, it asks the network for an address. If no one answers, Windows gives itself a "placeholder" address starting with **169.254**, which can't reach anything. Devices that were already connected keep their address for a while, which is why only restarted devices are affected.

## What to do

### If it's just your computer
1. Check the network cable is firmly plugged in at both ends (or Wi-Fi is on).
2. Restart the computer.
3. Still no connection → call the Service Desk.

### If several devices at your site are affected
1. **Call the Service Desk immediately** — this is treated as urgent.
2. **Stop restarting devices.** Devices that are still working will stay working for now; restarting them could take them down too.
3. Tell us: your store number, how many devices are affected, and whether any are still working.

## How to check your address (if we ask)
Start → type **cmd** → open Command Prompt → type `ipconfig` → read the **IPv4 Address** line to us.

---

### For Service Desk agents
1. `ipconfig /all` → 169.254.x.x, no gateway = APIPA; `ipconfig /renew` → "unable to contact your DHCP server".
2. **More than one device at a site = P1** (Impact 1 × Urgency 1). Start major-incident process.
3. Escalate to Windows Server Team immediately with: site, device count, one `ipconfig /all`, time it started.
4. Server-side checks (Tier 2): `Get-Service DHCPServer`, `Get-DhcpServerInDC`, `Get-DhcpServerv4ScopeStatistics` (100% = exhausted), DHCP-Server events 1020/1063, and network/switch issues (Network Ops) if the server is healthy.
