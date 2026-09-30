# INC0010001 – User account repeatedly locked out

| Field | Value |
|---|---|
| Number | INC0010001 |
| Caller | Jacob Wilson (jacob.wilson) – Cashier, Store 0421 |
| Category / Subcategory | Access / Account Lockout |
| Configuration Item | Active Directory – corp.homelab.local |
| Contact type | Phone |
| Impact | 3 – Low (single user) |
| Urgency | 1 – High (cannot sign in to the register/back-office PC) |
| Priority | **P3 – Moderate** |
| Assignment group | Service Desk – Tier 1 |
| Assigned to | Arjun Mehta |
| State | Resolved |
| Linked KB | [KB0010001 – Account locked out](../kb/KB0010001-account-locked-out.md) |

## Short description
Account locked out repeatedly since password change yesterday.

## Description (as reported by the user)
> "I changed my password yesterday because it expired. This morning I got locked out, the store manager called you guys and you unlocked me, but it's locked again 20 minutes later. I'm typing the new password correctly. I can't clock in to the back-office PC."

## Work notes

| Time | Note |
|---|---|
| 2026-10-05 08:42 | Call received. Verified identity: employee ID 200102 + callback to store 0421 main line, confirmed with store manager Olivia Martin. |
| 08:44 | Checked account state: `Get-ADUser jacob.wilson -Properties LockedOut, badPwdCount, LastBadPasswordAttempt, AccountLockoutTime, PasswordLastSet`. Result: `LockedOut True`, `badPwdCount 5`, `AccountLockoutTime 08:37`, `PasswordLastSet` = yesterday 16:10. Second lockout today (first unlocked at 08:15). |
| 08:46 | Repeat lockout shortly after a password change points to a device still using the **old** password. Need the source before unlocking again, otherwise it will re-lock. |
| 08:47 | Ran `.\Get-LockoutSource.ps1 -Identity jacob.wilson -Hours 12` against PDC emulator DC01. Event ID 4740 x2, **Caller Computer Name: WS01** both times. |
| 08:49 | WS01 is the Head Office shared PC, not the store PC. Asked user: he used WS01 last week during training and mapped a drive with his credentials ("Remember my credentials" ticked). |
| 08:52 | Remote session to WS01 (user Priya Sharma currently signed in, permission obtained). `cmdkey /list` → `Domain:target=DC01` user `CORP\jacob.wilson`. `net use` → `Z: \\DC01\Departments\Public` reconnecting with stored credential. |
| 08:54 | Removed stale credential: `cmdkey /delete:DC01`. Removed persistent mapping: `net use Z: /delete`. Priya's own drives unaffected. |
| 08:55 | Unlocked: `Unlock-ADAccount jacob.wilson -Server DC01`. `Get-ADUser jacob.wilson -Properties LockedOut` → `False`. |
| 08:57 | User signed in to store PC WS02 successfully. |
| 09:25 | Follow-up check after 30 min: `LockedOut False`, `badPwdCount 0`, no new 4740 events. Also advised user to update password on his phone's work email/Wi-Fi profile if configured (none configured). |
| 09:26 | User confirmed working. Resolving. |

## Root cause
A persistent mapped drive on WS01 had Jacob's **old** password saved in Windows Credential Manager. Every reconnect attempt sent the old password to DC01; after 5 failures within 15 minutes the lockout policy locked the account.

## Resolution
Identified the lockout source from Event ID 4740 (Caller Computer Name) on the PDC emulator, removed the stale stored credential and mapped drive from WS01, unlocked the account, and monitored for 30 minutes with no further lockouts.

## Resolution code
Solved (Permanently)

## Tier 1 resolvable?
**Yes.** Unlock is delegated to GS-IT-Support; reading the Security log on the DC requires Event Log Readers membership (granted to the service desk in this lab). If Tier 1 cannot read DC logs, escalation note to Windows Server Team:

> Account jacob.wilson locked out twice today after password change 2026-10-04 16:10. Unlocked at 08:15, re-locked 08:37. Please identify Caller Computer Name from Event 4740 on the PDC emulator. User can't work until resolved (P3).

## Common sources of repeat lockouts (checked)
- Saved credentials / persistent mapped drives on another PC ✔ (this case)
- Phone email or Teams app still using the old password
- Wi-Fi profile using PEAP with domain credentials (caller shows as the NPS/RADIUS server or blank)
- Scheduled task or service running as the user
- Disconnected RDP session still signed in with old credentials

## How this scenario was reproduced in the lab
On WS01, signed in as `priya.sharma`, mapped `\\DC01\Departments\Public` as `CORP\jacob.wilson` with "Remember my credentials", changed Jacob's password on DC01, then ran `net use` reconnects until the account locked (threshold 5).
