# INC0010002 – Password reset for returning employee

| Field | Value |
|---|---|
| Number | INC0010002 |
| Caller | Mia Thompson (mia.thompson) – Department Supervisor, Store 0421 |
| Category / Subcategory | Access / Password Reset |
| Configuration Item | Active Directory – corp.homelab.local |
| Contact type | Phone |
| Impact | 3 – Low (single user) |
| Urgency | 1 – High (cannot sign in at start of shift) |
| Priority | **P3 – Moderate** |
| Assignment group | Service Desk – Tier 1 |
| Assigned to | Arjun Mehta |
| State | Resolved |
| Linked KB | [KB0010002 – Reset your password](../kb/KB0010002-reset-your-password.md) |

## Short description
Forgot password after two weeks of leave, cannot sign in.

## Description (as reported by the user)
> "I've just come back from two weeks off and I can't remember my password. I tried a few times and now it says my account is locked. I need to open the store at 7."

## Work notes

| Time | Note |
|---|---|
| 2026-10-06 06:41 | Call received from store 0421 main line. |
| 06:42 | Identity verification per process: (1) employee ID 200103 matched AD `EmployeeID`; (2) callback to the store number on file; (3) store manager Olivia Martin confirmed Mia is on shift. Verification **passed**. No answers recorded in ticket. |
| 06:43 | `Get-ADUser mia.thompson -Properties LockedOut, Enabled, PasswordExpired, PasswordLastSet, badPwdCount`. Result: `Enabled True`, `LockedOut True`, `PasswordExpired False`, `badPwdCount 5`. Lockout caused by her own attempts at WS02 (4740 caller WS02) – no other device involved. |
| 06:44 | Reset password with a one-time temporary password and forced change at next logon (performed with my standard account `arjun.mehta` via delegated GS-IT-Support rights, not a Domain Admin account). `Set-ADAccountPassword mia.thompson -Reset -NewPassword (Read-Host -AsSecureString)` ; `Set-ADUser mia.thompson -ChangePasswordAtLogon $true` ; `Unlock-ADAccount mia.thompson`. |
| 06:45 | Temporary password given verbally to the verified user only; not sent by email/text or stored in the ticket. |
| 06:47 | User signed in at WS02, prompted to change password, set new password meeting policy (12+ chars, complexity). `Get-ADUser mia.thompson -Properties PasswordLastSet` → today 06:47, `pwdLastSet` no longer 0. |
| 06:48 | Reminded user: update the password on her phone (Outlook/Teams) to avoid lockouts, and where to find the self-service reset KB. User confirmed signed in. Resolving. |

## Root cause
User forgot her password after extended leave; failed attempts triggered the lockout policy (5 attempts).

## Resolution
Verified identity (employee ID, callback, manager confirmation), unlocked the account, set a temporary password with "User must change password at next logon", and confirmed the user set her own password.

## Resolution code
Solved Remotely

## Tier 1 resolvable?
**Yes.** Password reset and unlock are delegated to GS-IT-Support on OU=Corp.

**Escalate instead if:** identity cannot be verified (to the user's manager / Security per process), the account is disabled (may be an HR leaver – check with HR, do not enable), or the account is privileged (`adm.*` – IT Admins reset their own through a Tier 2 admin).

## How this scenario was reproduced in the lab
Signed in to WS02 as `mia.thompson` with wrong passwords 5 times to lock the account, then performed the reset from WS01 with RSAT as `arjun.mehta` to prove the delegation works without Domain Admin rights.
