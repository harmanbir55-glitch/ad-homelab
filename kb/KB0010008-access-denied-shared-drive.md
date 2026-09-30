# KB0010008 – "Access denied" or "You need permission" on a shared drive

| | |
|---|---|
| **Article** | KB0010008 |
| **Audience** | All employees |
| **Applies to** | Shared drives (F:, H:, M:, S:, P:) |
| **Related incident** | [INC0010008](../tickets/INC0010008-share-access-denied.md) |
| **Last reviewed** | 2026-10 |

## What you'll see
- "Access is denied" or "You need permission to perform this action."
- You can **open** a file but can't **save** it.
- You can see a folder but can't open it.

## First, is this expected?
Access to each team folder is given by team. Some people have **read-only** access (can open, can't save) — for example, Accounts Payable can view some Finance files but not change them.

## What to do

1. **Try saving a copy** (File → Save As) to your Desktop so you don't lose your work.
2. **Check whether someone else has the file open.** You may see "locked for editing by …". Wait or ask them to close it.
3. **Did you ever have save access to this folder?**
   - **No, you need it now** → ask your manager to submit an **Access Request** in the portal.
   - **Yes, it worked before** → call the Service Desk. Tell us the **full folder path**, the **exact error**, and whether **colleagues** have the same problem. If several people are affected, say so — it's handled with higher priority.

---

### For Service Desk agents
1. `Get-ADPrincipalGroupMembership <user>` → correct GS-*-RW / RO group?
2. `whoami /groups` on the user's session → group in token? (Not → sign out/in, see KB0010004.)
3. Test with another member of the same group. **Multiple users → raise impact, escalate** to Windows Server Team.
4. Server team: compare **share** (`Get-SmbShareAccess <share>`) and **NTFS** (`icacls <path>`); use Advanced Security → **Effective Access** (check the *Access limited by* column). Over the network the **most restrictive** of share and NTFS applies. Standard: share = Authenticated Users Change, NTFS via GS-* groups.
