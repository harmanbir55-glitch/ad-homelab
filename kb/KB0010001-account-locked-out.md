# KB0010001 – My account is locked out (or keeps locking)

| | |
|---|---|
| **Article** | KB0010001 |
| **Audience** | All employees |
| **Applies to** | Windows sign-in, shared drives, Outlook, Teams, Wi-Fi |
| **Related incident** | [INC0010001](../tickets/INC0010001-account-lockout.md) |
| **Last reviewed** | 2026-10 |

## What you'll see
- "The referenced account is currently locked out and may not be logged on to."
- You're sure your password is right, but you still can't sign in.
- You were unlocked, and a short time later it happened again.

## Why this happens
For security, your account locks for **15 minutes** after **5 wrong password attempts**. Those attempts don't have to come from you typing. If a phone, another computer, or a saved login is still using your **old** password, it keeps trying in the background and locks you out.

## What to do

1. **Wait 15 minutes.** The lock clears by itself. Then sign in carefully (check Caps Lock and the keyboard language).
2. **If you need in sooner, call the Service Desk.** We'll verify who you are and unlock you straight away.
3. **If it keeps happening after a password change,** update the new password everywhere you use it:
   - **Phone:** Outlook / email app, Teams, and the company Wi-Fi (forget the network and reconnect).
   - **Other computers** you've signed in to recently (a shared back-office PC, a laptop).
   - **Saved passwords on a PC:** Start → type **Credential Manager** → **Windows Credentials** → remove entries for company servers. You'll be asked to sign in again.
4. **Sign out** of any computer you're not using, rather than just locking it.

## Tips to prevent it
- After changing your password, update your phone **the same day**.
- Don't tick "Remember my credentials" on shared computers.

## Still stuck?
Call the Service Desk and mention this article (KB0010001). Have your employee ID ready.

---

### For Service Desk agents
1. Verify identity (employee ID + callback / manager confirmation).
2. Check state: `Get-ADUser <user> -Properties LockedOut, badPwdCount, AccountLockoutTime, PasswordLastSet`.
3. **Repeat lockout?** Find the source before unlocking: `scripts\Get-LockoutSource.ps1 -Identity <user>` (Event 4740 on the PDC emulator, *Caller Computer Name*). Blank caller → phone / Wi-Fi (NPS) likely.
4. Remove the source (stale credential, mapped drive, phone profile), then `Unlock-ADAccount <user>`.
5. Re-check after 15–30 minutes. Escalate to Windows Server Team if the source is a server or service you can't access.
