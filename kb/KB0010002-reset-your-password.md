# KB0010002 – I forgot my password / need a password reset

| | |
|---|---|
| **Article** | KB0010002 |
| **Audience** | All employees |
| **Applies to** | Windows / company account password |
| **Related incident** | [INC0010002](../tickets/INC0010002-password-reset.md) |
| **Last reviewed** | 2026-10 |

## Before you call
If you remember your current password and just want to change it: press **Ctrl + Alt + Delete → Change a password**.

## Getting a reset from the Service Desk

1. **Call the Service Desk** from your store or department phone if you can.
2. **We'll confirm who you are.** Expect to give your employee ID; we may call you back on a number we have on file or confirm with your manager. This protects your account from someone pretending to be you.
3. **We'll give you a temporary password** — only to you, by voice. We will never email it or text it to a personal number.
4. **Sign in with the temporary password.** Windows will ask you to **set a new password straight away**.
5. Your new password must:
   - be at least **12 characters**
   - use three of: uppercase, lowercase, numbers, symbols
   - not match any of your last 24 passwords
   - not contain your name or username

   💡 A short sentence is easy to remember and strong: `Paint-aisle-opens-at-7!`

6. **Update your phone** (Outlook, Teams, Wi-Fi) with the new password, or it may lock your account — see [KB0010001](KB0010001-account-locked-out.md).

## Important
- The Service Desk will **never** ask for your current password.
- Never share your password, even with a manager or IT.

---

### For Service Desk agents
1. Verify identity per process: employee ID matches `EmployeeID` in AD **plus** callback to number on file or manager confirmation. Record the *method* in work notes, never the answers.
2. Check `Enabled`, `LockedOut`, `PasswordExpired`. **Disabled account → do not enable**; check HR status and escalate.
3. Reset with your standard (delegated) account, not a Domain Admin account:
   ```powershell
   Set-ADAccountPassword <user> -Reset -NewPassword (Read-Host -AsSecureString 'Temp password')
   Set-ADUser <user> -ChangePasswordAtLogon $true
   Unlock-ADAccount <user>
   ```
   GUI: ADUC → user → **Reset Password** → tick **User must change password at next logon** and **Unlock the user's account**.
4. Stay on the line until the user has set their own password. Privileged `adm.*` accounts → escalate to Tier 2.
