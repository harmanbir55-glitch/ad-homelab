# INC0010003 – Store desktop restrictions not applying at Store 0421

| Field | Value |
|---|---|
| Number | INC0010003 |
| Caller | Olivia Martin (olivia.martin) – Store Manager, Store 0421 |
| Category / Subcategory | Software / Group Policy |
| Configuration Item | GPO: U-Stores-Desktop-Lockdown; WS02 |
| Contact type | Phone |
| Impact | 2 – Medium (all store users at one site) |
| Urgency | 3 – Low (users can work; compliance/security concern) |
| Priority | **P4 – Low** |
| Assignment group | Service Desk – Tier 1 → Windows Server Team |
| Assigned to | Arjun Mehta → Emily Chen |
| State | Resolved |
| Linked KB | [KB0010003 – Computer settings not updating](../kb/KB0010003-computer-settings-not-updating.md) |

## Short description
Store PCs no longer show company wallpaper; staff can open Settings/Control Panel.

## Description (as reported by the user)
> "Since yesterday the back-office PC has lost the NorthPeak wallpaper, and one of my associates changed the display settings. They're not supposed to be able to get into Settings. Nothing else seems wrong."

## Work notes

| Time | Note |
|---|---|
| 2026-10-07 10:05 | Call received. Confirmed with caller this affects all store users on WS02 (tested Olivia and Noah). Head Office unaffected. |
| 10:08 | Remote session to WS02 as noah.davis. `gpupdate /force` → "User Policy update has completed successfully". Restrictions still missing, so not just a missed refresh. |
| 10:10 | `gpresult /r /scope user`. **Applied GPOs:** U-Drive-Mappings, Default Domain Policy. **"The following GPOs were not applied because they were filtered out":** `U-Stores-Desktop-Lockdown – Filtering: Denied (Security)`. The GPO is linked and reaches the user, but security filtering excludes him. |
| 10:12 | `gpresult /h C:\Temp\gp-ws02.html /f` attached. Event Viewer → Applications and Services Logs → Microsoft → Windows → GroupPolicy → Operational: Event **5313** lists U-Stores-Desktop-Lockdown as filtered out (Denied Security). |
| 10:14 | Tier 1 cannot change GPOs. Escalated to Windows Server Team (note below). |
| 10:40 | (Emily Chen) GPMC → U-Stores-Desktop-Lockdown → Scope. Security Filtering contains only `GS-Store-Pilot` (a group from a pilot last week, no members). **Authenticated Users** was removed and not replaced. Delegation tab: Domain Computers still had Read. |
| 10:42 | Change CHG0010012 (standard change, pre-approved): Security Filtering → removed GS-Store-Pilot, added back Authenticated Users (Read + Apply). PowerShell: `Set-GPPermission -Name 'U-Stores-Desktop-Lockdown' -TargetName 'Authenticated Users' -TargetType Group -PermissionLevel GpoApply`. |
| 10:45 | On WS02: `gpupdate /force`, sign out/in as noah.davis. `gpresult /r` → U-Stores-Desktop-Lockdown under **Applied Group Policy Objects**. Wallpaper restored, Settings blocked with "This operation has been cancelled due to restrictions in effect on this computer". |
| 10:47 | Caller confirmed. Resolving. |

## Root cause
During a pilot, Authenticated Users was removed from the GPO's **security filtering** and replaced with a pilot group that had no members. The GPO was still linked to the Stores OU, but no store user had the *Apply group policy* permission, so it was filtered out for everyone.

## Resolution
Restored Authenticated Users to security filtering under a standard change, forced a policy refresh, and confirmed the GPO applied via gpresult.

## Resolution code
Solved (Permanently)

## Tier 1 resolvable?
**No – diagnosis at Tier 1, fix at Windows Server Team** (GPO edits are restricted). Escalation note:

> Store 0421 users (tested noah.davis, olivia.martin on WS02) not receiving U-Stores-Desktop-Lockdown. gpresult /r shows "Filtering: Denied (Security)"; GroupPolicy/Operational Event 5313 confirms. gpupdate /force done, no change. Please review security filtering on the GPO. HTML report attached. P4, store is operating normally.

## Other causes checked (and how they look)

| Cause | How it shows in gpresult / GPMC | Fix |
|---|---|---|
| **Wrong OU link** – GPO linked to Head Office instead of Stores | GPO doesn't appear in gpresult at all (neither applied nor filtered). GPMC → Scope → Links shows the wrong OU. | Link to OU=Stores, remove the wrong link |
| **Security filtering removed** (this ticket) | "Filtering: Denied (Security)", Event 5313 | Restore Authenticated Users or the right group |
| **Missing Read for computers** (MS16-072) – filtered to a user group but Domain Computers/Authenticated Users has no Read | GPO silently missing; Event 5313/7016 | Delegation tab → add Domain Computers **Read** |
| **User vs computer mix-up** – store wallpaper configured under *Computer* Configuration, or user settings linked to an OU that only holds computers | "Filtering: Disabled (GPO)" when the half is disabled, or the GPO shows under Computer Settings with no user effect | Move the setting to the correct half, or link to the OU holding the users (loopback only when intended) |
| **WMI filter false** | "Filtering: Denied (WMI Filter)" | Fix the WMI query |

## How this scenario was reproduced in the lab
GPMC → U-Stores-Desktop-Lockdown → Scope → removed Authenticated Users and added an empty group, then signed in to WS02 as a store user. The two variants were reproduced by moving the link to Head Office, and by recreating the wallpaper setting under Computer Configuration in the user-only GPO.
