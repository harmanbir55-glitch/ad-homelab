# KB0010007 – "The trust relationship between this workstation and the primary domain failed"

| | |
|---|---|
| **Article** | KB0010007 |
| **Audience** | All employees |
| **Applies to** | Company Windows computers |
| **Related incident** | [INC0010007](../tickets/INC0010007-trust-relationship-failed.md) |
| **Last reviewed** | 2026-10 |

## What you'll see
At the sign-in screen: **"The trust relationship between this workstation and the primary domain failed."**

## What it means
Your **account is fine** — this is a problem with the **computer's** connection to the company network. Every company computer has its own hidden "password" that it shares with the company directory. If they get out of step (for example, after the computer is restored from a backup, or has been switched off for many weeks), the network stops trusting it.

## What to do

1. **Don't keep retrying** — it won't work and could lock your account.
2. **Use a different company computer** if one is available. You can sign in there normally.
3. **Call the Service Desk** with:
   - the computer name (sticker on the device)
   - whether the computer was recently repaired, restored, or unused for a long time
4. A Desktop Support technician will reconnect the computer. This usually takes **10–15 minutes**, doesn't need a reinstall, and **your files and settings stay as they are**.

## Prevent it
Laptops that aren't used for a long time should be switched on and connected to the company network at least **once a month**.

---

### For Service Desk agents
1. Confirm it's the device: user signs in fine on another PC; other users fail on this PC.
2. `Get-ADComputer <PC> -Properties Enabled, PasswordLastSet` — note date; disabled/deleted object is a different problem.
3. Needs local admin → escalate to Desktop Support. Fix (as local admin on the PC):
   ```powershell
   Test-ComputerSecureChannel -Verbose                                     # False
   Test-ComputerSecureChannel -Repair -Credential CORP\<admin account>     # True
   nltest /sc_verify:corp.homelab.local                                    # NERR_Success
   ```
4. Avoid unjoin/rejoin unless Repair fails.
