# KB0010004 – A shared drive (F:, H:, M:, S:, P:) is missing

| | |
|---|---|
| **Article** | KB0010004 |
| **Audience** | All employees |
| **Applies to** | Mapped network drives on company computers |
| **Related incident** | [INC0010004](../tickets/INC0010004-mapped-drive-missing.md) |
| **Last reviewed** | 2026-10 |

## Which drive should I have?

| Drive | Folder | Who gets it |
|---|---|---|
| P: | Public | Everyone |
| F: | Finance | Finance team |
| H: | HR | HR team |
| M: | Merchandising | Merchandising team |
| S: | Store Ops | Store managers, district managers, store staff (read only) |

Drives appear automatically based on your team. You won't see drives for teams you're not part of.

## What to do

**Just got access approved?**
Your access is loaded when you sign in, so a new approval isn't picked up until you **sign out and sign back in**. Save your work, then Start → your name → **Sign out**. Sign back in and open File Explorer → **This PC**.

**Had the drive before and it vanished, or shows a red ❌?**
1. Check you're connected to the company network.
2. Double-click the drive — a red ❌ often clears once it reconnects.
3. Sign out and back in.
4. Still missing: call the Service Desk.

**Never had it and need it?**
Ask your manager to submit an **Access Request** in the portal. The Service Desk can't add access without manager approval.

## Tip
Don't map drives yourself with "Map network drive" — if the server changes, your personal mapping breaks. The official drives update automatically.

---

### For Service Desk agents
1. AD first: `Get-ADPrincipalGroupMembership <user> | Select Name` — is the right GS-* group there? No → access request needed.
2. Token second: on the user's session `whoami /groups | findstr /i GS-`. Group in AD but **not** in `whoami` → stale token → sign out/in.
3. `gpresult /r /scope user` → U-Drive-Mappings applied? Group listed?
4. If group, token and GPO are all correct and the drive still doesn't map → escalate to Windows Server Team with the outputs (drive-map targeting may be wrong).
