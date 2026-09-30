# INC0010008 – "Access denied" when saving to the Finance shared folder

| Field | Value |
|---|---|
| Number | INC0010008 |
| Caller | Daniel Brooks (daniel.brooks) – Finance Manager, Head Office |
| Category / Subcategory | Access / Permissions |
| Configuration Item | \\DC01\Departments (share) |
| Contact type | Phone |
| Impact | 3 → **2** – Medium (raised after confirming all write users affected) |
| Urgency | 2 – Medium (can read files; saves locally as workaround) |
| Priority | P4 → **P3 – Moderate** |
| Assignment group | Service Desk – Tier 1 → Windows Server Team |
| Assigned to | Arjun Mehta → Emily Chen |
| State | Resolved |
| Linked KB | [KB0010008 – Access denied on a shared drive](../kb/KB0010008-access-denied-shared-drive.md) |

## Short description
Finance users can open but not save files on F: – access denied.

## Description (as reported by the user)
> "I can open the budget spreadsheet on the F: drive, but when I save it says I don't have permission. I've been editing this file every day for months. Month-end close is Thursday."

## Work notes

| Time | Note |
|---|---|
| 2026-10-15 14:10 | Call received. Identity verified. Priority P4 (single user, workaround). |
| 14:12 | Group check: `Get-ADPrincipalGroupMembership daniel.brooks` → **GS-Finance-RW** present (modify access). `whoami /groups` on his session also shows it → not a membership or token problem. |
| 14:14 | Tested with colleague priya.sharma (also GS-Finance-RW): same error saving a new file. **Impact raised to 2, priority P3.** |
| 14:15 | Tier 1 cannot view server ACLs → escalated to Windows Server Team (note below). |
| 14:30 | (Emily Chen) NTFS check: `icacls C:\Shares\Departments\Finance` → `CORP\GS-Finance-RW:(OI)(CI)(M)` – NTFS grants Modify. |
| 14:31 | Share check: `Get-SmbShareAccess Departments` → `Authenticated Users – Allow – **Read**`. Expected **Change**. |
| 14:32 | Advanced Security → Effective Access for daniel.brooks on the share path: write permissions unticked, **Access limited by: Share**. When both apply, the most restrictive of share and NTFS wins → effective Read. |
| 14:33 | Checked change calendar: no approved change for this share. Server team confirmed the share permission was edited yesterday during an unrecorded "tighten access" task. |
| 14:35 | Fix under emergency change CHG0010015: `Revoke-SmbShareAccess -Name Departments -AccountName 'Authenticated Users' -Force` ; `Grant-SmbShareAccess -Name Departments -AccountName 'Authenticated Users' -AccessRight Change -Force`. |
| 14:37 | daniel.brooks saved the budget file. Verified a read-only user (aisha.khan, GS-Finance-RO) still **cannot** save – NTFS continues to enforce least privilege. |
| 14:38 | Caller confirmed. Resolving. Informed Server team lead about unrecorded change. |

## Root cause
The share permission on `\\DC01\Departments` was changed from Authenticated Users = Change to Read without a change record. Share and NTFS permissions combine and the **most restrictive** applies over the network, so users with NTFS Modify were limited to Read.

## Resolution
Restored the share permission to Change for Authenticated Users (the documented standard; NTFS groups do the real access control), then verified both a read-write and a read-only user got the correct access.

## Resolution code
Solved (Permanently)

## Tier 1 resolvable?
**No – Tier 1 rules out group membership/token, then escalates.** Escalation note:

> Finance write users (daniel.brooks, priya.sharma) can read but not save in \\DC01\Departments\Finance. Both in GS-Finance-RW, whoami /groups confirms. Not user-specific. Please check share vs NTFS permissions on Departments. Month-end Thursday. P3.

## NTFS vs share – quick reference

| Share | NTFS | Effective over network |
|---|---|---|
| Change | Modify | Modify |
| **Read** | **Modify** | **Read** (this ticket) |
| Change | Read | Read |
| Full | none | **No access** |

Locally on the server, only NTFS applies.

## How this scenario was reproduced in the lab
On DC01: `Revoke-SmbShareAccess -Name Departments -AccountName 'Authenticated Users' -Force; Grant-SmbShareAccess -Name Departments -AccountName 'Authenticated Users' -AccessRight Read -Force`, then attempted to save as daniel.brooks on WS01.
