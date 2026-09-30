# KB0010005 – Websites work but shared drives and company apps don't

| | |
|---|---|
| **Article** | KB0010005 |
| **Audience** | All employees |
| **Applies to** | Company Windows computers in offices and stores |
| **Related incident** | [INC0010005](../tickets/INC0010005-dns-cannot-find-domain.md) |
| **Last reviewed** | 2026-10 |

## What you'll see
- The internet works, but shared drives show a red ❌ or "The network path was not found."
- Messages like "The domain is not available" or "We can't sign you in to your account" appear.
- It often starts after someone else (a vendor, a technician, a VPN or "network booster" app) changed something on the computer.

## Why this happens
Your computer finds company servers by asking the company's own directory ("DNS"). If the computer is set to ask a public service instead, it can still find websites but **can't find anything inside the company**.

## What to do

1. **Restart the computer.** This fixes a temporary glitch.
2. **Check you're on the company network,** not a phone hotspot or guest Wi-Fi.
3. **Don't change network settings yourself** — you'll need IT for this one.
4. **Call the Service Desk.** Tell us:
   - the computer name
   - whether anyone recently worked on the computer or installed software
   - that websites work but company resources don't (this saves a lot of time)

We'll usually fix it remotely in a few minutes.

---

### For Service Desk agents
"Internet works, domain doesn't" = check DNS first.

```powershell
ipconfig /all                                      # DNS must be the DC (10.10.10.10), not 8.8.8.8 / router
nltest /dsgetdc:corp.homelab.local                 # 1355 ERROR_NO_SUCH_DOMAIN = can't find a DC
Resolve-DnsName _ldap._tcp.dc._msdcs.corp.homelab.local -Type SRV
Test-NetConnection 10.10.10.10 -Port 445           # proves routing is fine
```

Fix (elevated):
```powershell
Set-DnsClientServerAddress -InterfaceAlias Ethernet -ResetServerAddresses
ipconfig /flushdns; ipconfig /registerdns; gpupdate /force
```
No remote admin rights → escalate to Desktop Support with the outputs above.
