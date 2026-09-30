# INC0010009 – Sign-in fails: "time and/or date difference between the client and server"

| Field | Value |
|---|---|
| Number | INC0010009 |
| Caller | Sofia Alvarez (sofia.alvarez) – HR Manager, Head Office |
| Category / Subcategory | Software / Operating System |
| Configuration Item | WS01 |
| Contact type | Phone |
| Impact | 3 – Low (single workstation) |
| Urgency | 1 – High (cannot sign in) |
| Priority | **P3 – Moderate** |
| Assignment group | Service Desk – Tier 1 → Desktop Support – Tier 2 |
| Assigned to | Arjun Mehta → Emily Chen |
| State | Resolved |
| Linked KB | [KB0010009 – Time/date difference error](../kb/KB0010009-time-date-difference-error.md) |

## Short description
WS01: domain sign-in fails with time/date difference error; clock ~12 minutes fast.

## Description (as reported by the user)
> "When I try to sign in it says 'There is a time and/or date difference between the client and server.' I noticed the clock on this PC is wrong – it says 9:27 but my phone says 9:15."

## Work notes

| Time | Note |
|---|---|
| 2026-10-16 09:15 | Call received. Identity verified. User's observation (PC clock 12 minutes ahead) matches the error. |
| 09:16 | Checked DC time is correct and other PCs are fine: `w32tm /query /status` on DC01 → Source `time.windows.com`, stratum 3, last sync 08:52. WS02 signs in normally → isolated to WS01. |
| 09:17 | Explanation: domain sign-in uses **Kerberos**, which rejects requests when the client and DC clocks differ by more than **5 minutes** (default "Maximum tolerance for computer clock synchronization"). This protects against replay attacks. |
| 09:18 | User can't sign in with a domain account → needs local admin. Escalated to Desktop Support (note below). |
| 09:25 | (Emily Chen) Signed in to WS01 as `.\labadmin`. `Get-Date` → 09:37 vs DC 09:25. `w32tm /stripchart /computer:dc01.corp.homelab.local /samples:3 /dataonly` → offset **-723 s**. |
| 09:26 | `w32tm /query /source` → `Local CMOS Clock`. Client is **not** syncing from the domain hierarchy. `Get-Service W32Time` → Stopped, StartType Disabled. System log: Kerberos error KRB_AP_ERR_SKEW (0x25) events for DC01. |
| 09:27 | Hypervisor check: WS01 "Time synchronization" integration service disabled, so no host sync either. |
| 09:28 | Fix: `Set-Service W32Time -StartupType Automatic; Start-Service W32Time` ; `w32tm /config /syncfromflags:domhier /update` ; `w32tm /resync /force`. |
| 09:29 | `w32tm /query /source` → `DC01.corp.homelab.local`. `w32tm /stripchart ... /samples:3` → offset < 0.1 s. |
| 09:31 | Signed out. sofia.alvarez signed in successfully; `klist` shows a TGT from DC01; H: mapped. |
| 09:32 | Caller confirmed. Resolving. Problem note: find out who disabled W32Time on WS01 (possible imaging/hardening script). |

## Root cause
The Windows Time service on WS01 had been disabled (and host time sync was off), so the clock drifted/was set 12 minutes ahead. Kerberos authentication fails when client–DC skew exceeds 5 minutes.

## Resolution
Re-enabled the Windows Time service, configured it to sync from the domain hierarchy (`/syncfromflags:domhier`), forced a resync, and confirmed Kerberos sign-in.

## Resolution code
Solved (Permanently)

## Tier 1 resolvable?
**Partly.** Tier 1 can recognise the error and confirm DC time and other PCs are correct. The fix needs local admin → Desktop Support. Escalation note:

> WS01: "time and/or date difference" at sign-in, clock ~12 min fast per user. DC time correct, other PCs OK. Needs local admin to resync time (w32tm) – likely W32Time not running. P3.

## How domain time should work

```text
Internet NTP (time.windows.com) --> PDC emulator (DC01) --> other DCs --> member servers & workstations
                                    w32tm /config /manualpeerlist:"time.windows.com,0x8"
                                          /syncfromflags:manual /reliable:yes /update
```

Hypervisor time sync on a DC VM can fight with this; on Hyper-V, disabling the VMIC time provider on the DC (so it uses NTP) is common practice. Clients should use `domhier`.

## How this scenario was reproduced in the lab
Disabled WS01's hypervisor time synchronization, then on WS01 as local admin: `Stop-Service W32Time; Set-Service W32Time -StartupType Disabled; Set-Date (Get-Date).AddMinutes(12)`. Signed out and attempted domain sign-in as sofia.alvarez.
