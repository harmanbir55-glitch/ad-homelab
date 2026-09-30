# INC0010004 – Finance mapped drive (F:) missing for one user

| Field | Value |
|---|---|
| Number | INC0010004 |
| Caller | Aisha Khan (aisha.khan) – Accounts Payable Clerk, Head Office |
| Category / Subcategory | Access / Permissions |
| Configuration Item | GPO: U-Drive-Mappings; \\DC01\Departments\Finance |
| Contact type | Self-service portal |
| Impact | 3 – Low (single user) |
| Urgency | 2 – Medium (can receive files by email as a workaround) |
| Priority | **P4 – Low** |
| Assignment group | Service Desk – Tier 1 |
| Assigned to | Arjun Mehta |
| State | Resolved |
| Linked KB | [KB0010004 – Mapped drive missing](../kb/KB0010004-mapped-drive-missing.md) |

## Short description
F: Finance drive not showing after access request was approved.

## Description (as reported by the user)
> "My manager requested Finance drive access for me this morning and I got the email saying it's complete, but I still don't have an F: drive. Priya next to me has it."

## Work notes

| Time | Note |
|---|---|
| 2026-10-08 09:31 | Ticket received via portal. Linked request RITM0010037 (add aisha.khan to GS-Finance-RO) closed complete at 09:05. |
| 09:33 | Confirmed group membership in AD: `Get-ADPrincipalGroupMembership aisha.khan \| Select Name` → Domain Users, **GS-Finance-RO**. AD side is correct. |
| 09:35 | Remote session to WS01 with the user. `whoami /groups \| findstr /i finance` → **no result**. The user's logon token does not contain GS-Finance-RO. |
| 09:36 | Checked logon time: `quser` → logged on **08:28**, i.e. before the group was added at 09:05. Group memberships are read into the access token at sign-in; the drive-map item-level targeting and the file-server permission check both use that token. |
| 09:37 | `gpresult /r /scope user` → "The user is a part of the following security groups" list also lacks GS-Finance-RO; U-Drive-Mappings shows as applied (targeting for F: evaluated false). |
| 09:38 | Asked user to save work, **sign out and back in** (a `gpupdate` alone does not refresh the token). |
| 09:41 | After sign-in: `whoami /groups` shows `CORP\GS-Finance-RO`. F: mapped to `\\DC01\Departments\Finance`. User can open files; saving is denied as expected (read-only role). Confirmed with user this matches the access requested. |
| 09:42 | Resolving. |

## Root cause
The user was added to GS-Finance-RO while she was already signed in. Windows builds the user's security token (list of groups) at sign-in, so the drive map's item-level targeting did not see the new group until she signed out and back in.

## Resolution
Confirmed correct group membership in AD, confirmed the stale token with `whoami /groups`, had the user sign out and in. F: mapped with the expected read-only access.

## Resolution code
Solved (Permanently)

## Tier 1 resolvable?
**Yes.**

**Escalate to Windows Server Team if:** the group is correct, the user has signed out/in, and gpresult shows U-Drive-Mappings not applied or the targeting is wrong — that points to the GPO configuration. Also check replication if there are multiple DCs (group change made on a DC the client isn't using yet).

## Tip
Before telling a user to reboot, `whoami /groups` answers "is it a token problem?" in 5 seconds. For access to the share (not the drive letter), `klist purge` plus reconnecting can refresh Kerberos tickets without a full sign-out.

## How this scenario was reproduced in the lab
Removed aisha.khan from GS-Finance-RO, signed her in to WS01, then added her back to the group on DC01 while she remained signed in.
