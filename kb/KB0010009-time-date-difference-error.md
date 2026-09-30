# KB0010009 – "There is a time and/or date difference between the client and server"

| | |
|---|---|
| **Article** | KB0010009 |
| **Audience** | All employees |
| **Applies to** | Company Windows computers |
| **Related incident** | [INC0010009](../tickets/INC0010009-time-skew-kerberos.md) |
| **Last reviewed** | 2026-10 |

## What you'll see
- At sign-in: **"There is a time and/or date difference between the client and server. Please try again or consult your system administrator."**
- The clock in the corner of the screen doesn't match your phone.

## Why this happens
For security, the company network only accepts sign-ins from computers whose clock is within **5 minutes** of the network's clock. If the computer's clock is wrong — a flat internal battery, a manual change, or a time-zone mistake — you can't sign in.

## What to do

1. **Compare the computer's clock with your phone.** Note how far off it is (time, date, and time zone).
2. **Restart the computer** while connected to the company network. It will often correct its clock automatically.
3. **Still getting the error?** Call the Service Desk and tell us:
   - the computer name
   - how far off the clock is
   - whether the date is wrong too (a wrong date after the PC was unplugged can mean the internal battery needs replacing)

Please don't change the time or time zone yourself unless the Service Desk asks you to.

---

### For Service Desk agents
1. Confirm DC time is correct and other PCs sign in → isolated device.
2. Needs local admin → escalate to Desktop Support. On the PC:
   ```powershell
   w32tm /query /source            # "Local CMOS Clock" = not syncing with the domain
   Get-Service W32Time             # must be Running / Automatic
   Set-Service W32Time -StartupType Automatic; Start-Service W32Time
   w32tm /config /syncfromflags:domhier /update
   w32tm /resync /force
   w32tm /stripchart /computer:dc01.corp.homelab.local /samples:3 /dataonly
   ```
3. Kerberos maximum tolerance is 5 minutes. Repeated drift after a reboot → hardware CMOS battery (Hardware ticket).
