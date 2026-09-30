# KB0010003 – Company settings missing on a computer (wallpaper, restrictions, printers)

| | |
|---|---|
| **Article** | KB0010003 |
| **Audience** | All employees, store managers |
| **Applies to** | Windows 11 company computers |
| **Related incident** | [INC0010003](../tickets/INC0010003-gpo-not-applying.md) |
| **Last reviewed** | 2026-10 |

## What you might notice
- The NorthPeak wallpaper has disappeared from a store computer.
- Staff can open Settings or Control Panel on a store PC when they normally can't.
- A setting IT pushed out (a shortcut, a printer, a drive) isn't there.

## Why this happens
Company computers get their settings automatically from the network every 90 minutes and each time someone signs in. If a computer was off the network, or a setting was just changed by IT, it may not have picked it up yet.

## What to do

1. **Make sure the computer is connected** to the store or office network (not a hotspot).
2. **Refresh the settings:**
   - Click **Start**, type **cmd**, and open **Command Prompt**.
   - Type `gpupdate /force` and press **Enter**.
   - Wait for "Computer Policy update has completed successfully" and "User Policy update has completed successfully".
3. **Sign out and sign back in.** Some settings, like the wallpaper, only apply at sign-in. If asked to restart, restart.
4. **Still missing?** Call the Service Desk and tell us:
   - the computer name (Start → Settings is blocked on store PCs, so look for the sticker on the PC, or run `hostname` in Command Prompt)
   - whether it affects **one person** or **everyone** on that computer
   - when you first noticed

## Please don't
Try to change the wallpaper or security settings yourself. Store PCs are locked down to protect customer and payment data.

---

### For Service Desk agents
1. Scope it: one user, one PC, or a whole site/OU?
2. On the PC: `gpupdate /force`, then `gpresult /r` (use `/scope user` or `/scope computer`).
   - GPO **not listed at all** → not linked to the OU the user/computer is in. Check `Get-ADUser <user>` DN.
   - **Filtering: Denied (Security)** → security filtering.
   - **Filtering: Denied (WMI Filter)** → WMI filter.
   - **Filtering: Disabled (GPO)** → that half of the GPO is disabled / setting in the wrong half.
3. `gpresult /h C:\Temp\gp.html /f` and Event Viewer → *Microsoft → Windows → GroupPolicy → Operational* (5312 applied list, 5313 filtered list). Attach both.
4. GPO changes are Windows Server Team only — escalate with the gpresult evidence.
