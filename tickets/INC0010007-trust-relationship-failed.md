# INC0010007 – "The trust relationship between this workstation and the primary domain failed"

| Field | Value |
|---|---|
| Number | INC0010007 |
| Caller | Noah Davis (noah.davis) – Sales Associate, Store 0421 |
| Category / Subcategory | Hardware / Workstation |
| Configuration Item | WS02 |
| Contact type | Phone |
| Impact | 3 – Low (one workstation; other store PCs work) |
| Urgency | 1 – High (no domain user can sign in on WS02) |
| Priority | **P3 – Moderate** |
| Assignment group | Service Desk – Tier 1 → Desktop Support – Tier 2 |
| Assigned to | Arjun Mehta → Emily Chen |
| State | Resolved |
| Linked KB | [KB0010007 – Trust relationship error](../kb/KB0010007-trust-relationship-error.md) |

## Short description
WS02: all users get trust relationship error at sign-in.

## Description (as reported by the user)
> "The back-office computer says 'The trust relationship between this workstation and the primary domain failed' when I sign in. My manager tried her login too and got the same message. It was restored from a backup by IT last week after it wouldn't start."

## Work notes

| Time | Note |
|---|---|
| 2026-10-14 11:02 | Call received. Identity verified. Asked user to try another PC: noah.davis signs in fine elsewhere → account OK, **computer** problem. Manager gets same error on WS02 → confirms device-specific. |
| 11:04 | `Get-ADComputer WS02 -Properties Enabled, PasswordLastSet, LastLogonDate` → Enabled True, **PasswordLastSet 2026-10-01 03:12**. The backup restored last week (2026-10-07) was taken on 2026-09-20, **before** that change. |
| 11:05 | Explanation: every domain computer has its own account password, changed automatically (default every 30 days) and stored in AD and on the PC. The restore put back an **older** machine password, so the PC and AD no longer agree and the secure channel fails. |
| 11:06 | Fix needs local admin on WS02 → escalated to Desktop Support (note below). Advised the store to use the other back-office PC meanwhile. |
| 11:20 | (Emily Chen) Signed in to WS02 with the local admin account `.\labadmin` (password retrieved from the password vault; LAPS in production). |
| 11:21 | `Test-ComputerSecureChannel -Verbose` → **False**. `nltest /sc_verify:corp.homelab.local` → `ERROR_NO_LOGON_SERVERS` / trust verification failed. |
| 11:22 | `Test-ComputerSecureChannel -Repair -Credential CORP\adm.emily.chen` → **True**. |
| 11:23 | `nltest /sc_verify:corp.homelab.local` → `Trusted DC Name \\DC01.corp.homelab.local`, `Trust Verification Status = 0 0x0 NERR_Success`. `Get-ADComputer WS02 -Properties PasswordLastSet` → updated to 11:22. |
| 11:25 | Signed out of local admin. noah.davis signed in successfully; drives mapped; GPOs applied (`gpresult /r`). No reboot or domain rejoin required. |
| 11:26 | Caller confirmed. Resolving. |

## Root cause
WS02 was restored from an image/checkpoint taken before its most recent automatic machine-account password change. The computer's stored password no longer matched its account in AD, breaking the secure channel.

## Resolution
Signed in with the local administrator account, repaired the secure channel with `Test-ComputerSecureChannel -Repair`, verified with `nltest /sc_verify`, and confirmed domain sign-in.

## Resolution code
Solved Remotely

## Tier 1 resolvable?
**No – escalate to Desktop Support** (needs local administrator on the device and domain credentials allowed to reset computer accounts). Tier 1 value-add is proving it's the device, not the user. Escalation note:

> WS02 (Store 0421): trust relationship failed for all users. User account works on other devices. WS02 was restored from backup last week; Backup image dated 2026-09-20; AD PasswordLastSet on WS02 = 2026-10-01. Needs local admin to run Test-ComputerSecureChannel -Repair. Store has one other back-office PC as workaround. P3.

## Alternatives (if Repair fails)

| Method | Notes |
|---|---|
| `Reset-ComputerMachinePassword -Server DC01 -Credential CORP\adm.emily.chen` | Same result, older cmdlet |
| `netdom resetpwd /s:DC01 /ud:CORP\adm.emily.chen /pd:*` | Works where PowerShell isn't available; reboot after |
| Unjoin to workgroup and rejoin | Last resort: requires reboots and can lose local profile association |

## How this scenario was reproduced in the lab
On DC01, ADUC → Corp → Stores → Store-0421 → Computers → right-click **WS02 → Reset Account**. (Restoring an old checkpoint of WS02 gives the same result.)
