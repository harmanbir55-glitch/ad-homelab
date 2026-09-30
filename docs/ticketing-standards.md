# Ticketing standards

These are the conventions used for every incident in [/tickets](../tickets) and every article in [/kb](../kb). They mirror a typical ServiceNow ITSM setup at a retail service desk.

## Priority: ITIL impact × urgency matrix

**Impact** is how many people or how much of the business is affected. **Urgency** is how quickly the business needs it fixed.

| | **Urgency 1 – High**<br>can't work, no workaround | **Urgency 2 – Medium**<br>degraded, workaround exists | **Urgency 3 – Low**<br>inconvenience |
|---|---|---|---|
| **Impact 1 – High**<br>site, store or department | **P1 – Critical** | P2 – High | P3 – Moderate |
| **Impact 2 – Medium**<br>a team or several users | P2 – High | P3 – Moderate | P4 – Low |
| **Impact 3 – Low**<br>one user | P3 – Moderate | P4 – Low | P5 – Planning |

Example targets (typical, adjust to your organisation's SLA):

| Priority | Respond | Resolve |
|---|---|---|
| P1 | 15 min | 4 h |
| P2 | 30 min | 8 h |
| P3 | 4 h | 2 business days |
| P4 | 1 business day | 5 business days |

In a store, a till or all store PCs being down is revenue-impacting, so it is scored as Impact 1 even if the store only has a handful of staff.

## Categories used

| Category | Subcategories |
|---|---|
| Access | Account Lockout, Password Reset, Permissions |
| Software | Group Policy, Operating System |
| Network | DNS, DHCP, Connectivity |
| Hardware | Workstation |

## Assignment groups

| Group | Handles |
|---|---|
| Service Desk – Tier 1 | First contact: resets, unlocks, basic diagnosis, KB-guided fixes |
| Desktop Support – Tier 2 | Hands-on workstation work, domain rejoin/repair, local admin tasks |
| Windows Server Team | DCs, DNS, DHCP, GPO changes, file server permissions |
| Network Operations | Switching, routing, Wi-Fi, firewalls |

## Resolution codes

| Code | Use when |
|---|---|
| Solved (Permanently) | Root cause fixed; will not recur |
| Solved (Work Around) | User working again, underlying cause still open (link a problem record) |
| Solved Remotely | Fixed via remote session / admin tools |
| Not Solved (Not Reproducible) | Could not reproduce after investigation |
| Closed/Resolved by Caller | User fixed it themselves |

## Work-note conventions

- Timestamp every entry (`YYYY-MM-DD HH:MM`), in the order it happened.
- Record the **command**, the **relevant output**, and **what it tells you**. The next analyst should be able to pick up the ticket without calling the user again.
- Never paste passwords, full MFA codes or personal data into a ticket.
- Identity verification is always noted (method, not the answers).

## Ticket template

```markdown
# INC00100XX – <short description>

| Field | Value |
|---|---|
| Number | INC00100XX |
| Caller | |
| Category / Subcategory | |
| Configuration Item | |
| Contact type | Phone / Self-service / Walk-up |
| Impact / Urgency / Priority | |
| Assignment group | |
| Assigned to | |
| State | Resolved |
| Linked KB | |

## Short description
## Description (as reported by the user)
## Work notes
## Root cause
## Resolution
## Resolution code
## Tier 1 resolvable?  /  Escalation note
## How this scenario was reproduced in the lab
```
