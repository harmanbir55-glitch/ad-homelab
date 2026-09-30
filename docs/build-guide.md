# Build guide

Step-by-step build of the lab, with the GUI path, the PowerShell equivalent, and **why** each step is done. Each phase ends with a "done when" checklist.

**Contents**

- [Phase 0 – Host and downloads](#phase-0--host-and-downloads)
- [Phase 1 – Virtual network and VMs](#phase-1--virtual-network-and-vms)
- [Phase 2 – DC01 and the new forest](#phase-2--dc01-and-the-new-forest)
- [Phase 3 – DNS, DHCP and NAT](#phase-3--dns-dhcp-and-nat)
- [Phase 4 – Clients and domain join](#phase-4--clients-and-domain-join)
- [Phase 5 – OUs, groups, users, file share](#phase-5--ous-groups-users-file-share)
- [Phase 6 – Group Policy](#phase-6--group-policy)
- [Phase 7 – Onboarding and offboarding automation](#phase-7--onboarding-and-offboarding-automation)
- [Phase 8 – Break/fix scenarios](#phase-8--breakfix-scenarios)
- [Optional phases](#optional-phases)

---

## Phase 0 – Host and downloads

| Item | Used here |
|---|---|
| Host | 16 GB RAM, 8 cores, SSD with 120 GB+ free, virtualization enabled in BIOS/UEFI |
| Hypervisor | Hyper-V (Windows 11 Pro/Enterprise) or VirtualBox 7.x |
| Windows Server 2022 Evaluation ISO | Microsoft Evaluation Center — 180-day evaluation. Must reach the internet in the first 10 days to activate. |
| Windows 11 Enterprise Evaluation ISO | Microsoft Evaluation Center — 90-day evaluation |
| VS Code + PowerShell extension, Git | Writing scripts and committing the repo |

Check the host (PowerShell as admin):

```powershell
Get-CimInstance Win32_Processor | Select Name, NumberOfCores, VirtualizationFirmwareEnabled
[math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB)
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All   # Hyper-V only
```

> ⚠️ Don't mix hypervisors. VirtualBox on a host with Hyper-V/WSL2/Memory Integrity enabled runs in a slow fallback mode.

**Done when:** virtualization is enabled, the hypervisor is installed, both ISOs are on an SSD.

---

## Phase 1 – Virtual network and VMs

**Why an isolated network:** the DC will run a DHCP server. On your home network it would compete with your router and hand out addresses that point every device at a DNS server that doesn't know the internet. The lab lives on its own virtual switch; only DC01 has a second NIC for internet.

### Networks

| Purpose | Hyper-V | VirtualBox |
|---|---|---|
| Lab (isolated) | Virtual Switch Manager → New → **Private**, name `LAB-Private` | Adapter → **Internal Network**, name `LAB` |
| Internet for DC01 | Built-in **Default Switch** | Adapter → **NAT** |

```powershell
# Hyper-V
New-VMSwitch -Name 'LAB-Private' -SwitchType Private
```

### VMs

| VM | vCPU | RAM | Disk | NICs | Notes |
|---|---|---|---|---|---|
| DC01 | 2 | 4 GB (dynamic 2–4) | 60 GB | LAB + NAT/Default Switch | Gen 2; **automatic checkpoints OFF** |
| WS01 | 2 | 4 GB (dynamic 2–4) | 64 GB | LAB only | Gen 2 + **virtual TPM** + Secure Boot |
| WS02 | 2 | 4 GB (dynamic 2–4) | 64 GB | LAB only | Gen 2 + virtual TPM + Secure Boot |

```powershell
# Hyper-V example for DC01 (repeat for clients with only the LAB switch)
New-VM -Name DC01 -Generation 2 -MemoryStartupBytes 4GB -NewVHDPath 'D:\Lab\VMs\DC01.vhdx' -NewVHDSizeBytes 60GB -SwitchName 'LAB-Private'
Add-VMNetworkAdapter -VMName DC01 -SwitchName 'Default Switch'
Set-VMProcessor -VMName DC01 -Count 2
Set-VM -Name DC01 -AutomaticCheckpointsEnabled $false
Add-VMDvdDrive -VMName DC01 -Path 'D:\Lab\ISO\Server2022-eval.iso'
Set-VMFirmware -VMName DC01 -FirstBootDevice (Get-VMDvdDrive -VMName DC01)

# Clients: Windows 11 needs a TPM
Set-VMKeyProtector -VMName WS01 -NewLocalKeyProtector
Enable-VMTPM -VMName WS01
```

> ⚠️ **Don't clone WS01 to make WS02** without Sysprep — duplicate SIDs cause domain-join problems. Install each client from the ISO.
>
> ⚠️ **Checkpoints and DCs:** restoring an old DC checkpoint in a multi-DC domain causes USN rollback. In this single-DC lab, a checkpoint before a risky change is fine — but restoring an old one can desync computer passwords (that's how Scenario 7 is reproduced).

**Done when:** three VMs exist, DC01 has two NICs, clients have one NIC on the lab network, clients have a TPM.

---

## Phase 2 – DC01 and the new forest

### 2.1 Install Windows Server

Choose **Windows Server 2022 Standard Evaluation (Desktop Experience)**. Without "Desktop Experience" you get Server Core (no GUI). Set the local Administrator password.

### 2.2 Static IP, DNS, rename

| GUI | PowerShell |
|---|---|
| `ncpa.cpl` → identify which adapter is the lab one (the one with a 169.254.x.x address, since there's no DHCP yet) → rename to **LAB** and the other to **WAN** | [`01-Set-DCBaseline.ps1`](../scripts/01-Set-DCBaseline.ps1) |
| LAB → IPv4 → IP `10.10.10.10` / `255.255.255.0`, **no gateway**, DNS `10.10.10.10`, alternate `127.0.0.1` | |
| WAN → IPv4 → Advanced → DNS tab → untick **Register this connection's addresses in DNS** | |
| Server Manager → Local Server → Computer name → `DC01` → restart | |

**Why:** the DC's IP is how every client finds it; it must never change. Only one NIC may register in DNS, otherwise clients get the NAT address for the DC and fail intermittently.

### 2.3 Install AD DS and promote

| GUI | PowerShell |
|---|---|
| Server Manager → Add Roles and Features → **Active Directory Domain Services** → Install | [`02-Install-ADDSForest.ps1`](../scripts/02-Install-ADDSForest.ps1) |
| Flag → **Promote this server to a domain controller** → **Add a new forest** → `corp.homelab.local` | |
| Functional level Windows Server 2016, DNS server ✔, Global Catalog ✔, DSRM password → Install | |

```powershell
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
Install-ADDSForest -DomainName corp.homelab.local -DomainNetbiosName CORP -InstallDns `
    -SafeModeAdministratorPassword (Read-Host -AsSecureString 'DSRM') -Force
```

**Why:** promotion creates the AD database (NTDS.dit), SYSVOL (where GPOs live), the DNS zone `corp.homelab.local`, and the SRV records clients use to find a DC. The DNS delegation warning is expected for a new forest.

**Verify after the reboot (log on as `CORP\Administrator`):**

```powershell
Get-ADDomain | Select DNSRoot, NetBIOSName, PDCEmulator, DomainMode
Get-Service NTDS, DNS, Netlogon, KDC | Select Name, Status
Resolve-DnsName _ldap._tcp.dc._msdcs.corp.homelab.local -Type SRV
dcdiag /q
```

**Done when:** you log on as `CORP\Administrator`, `Get-ADDomain` works, the SRV record resolves, `dcdiag /q` prints nothing.

---

## Phase 3 – DNS, DHCP and NAT

All three are in [`03-Configure-NetworkServices.ps1`](../scripts/03-Configure-NetworkServices.ps1).

### 3.1 NAT (internet for the lab)

| GUI | PowerShell |
|---|---|
| Add Roles → **Remote Access** → role service **Routing** | `Install-WindowsFeature RemoteAccess, Routing -IncludeManagementTools` |
| Tools → Routing and Remote Access → Configure → **NAT** → public interface **WAN** | `netsh routing ip nat install` / `add interface name="WAN" mode=full` / `add interface name="LAB" mode=private` |

**Why:** clients get default gateway `10.10.10.10` (DHCP option 003). DC01 translates their traffic out through the WAN NIC. The lab network itself stays invisible to your home network.

### 3.2 DNS

| Task | GUI (DNS Manager) | PowerShell |
|---|---|---|
| Reverse zone | Reverse Lookup Zones → New Zone → Primary, AD-integrated, forest-wide → `10.10.10` | `Add-DnsServerPrimaryZone -NetworkId 10.10.10.0/24 -ReplicationScope Forest` |
| PTR for DC01 | Reverse zone → New Pointer | `Add-DnsServerResourceRecordPtr -ZoneName 10.10.10.in-addr.arpa -Name 10 -PtrDomainName dc01.corp.homelab.local.` |
| Forwarders | Server → Properties → Forwarders → `1.1.1.1`, `8.8.8.8` | `Set-DnsServerForwarder -IPAddress 1.1.1.1,8.8.8.8` |
| Scavenging | Server → Set Aging/Scavenging for All Zones | `Set-DnsServerScavenging -ScavengingState $true -ApplyOnAllZones` |

**Why:** forward zone = name → IP (and the SRV records AD needs). Reverse zone = IP → name (nslookup shows "UnKnown" without it). Forwarders = where the DC sends queries for names it doesn't own, i.e. the internet. Clients **never** use public DNS directly.

### 3.3 DHCP

| Task | GUI (DHCP console) | PowerShell |
|---|---|---|
| Install | Add Roles → DHCP Server → **Complete DHCP configuration** | `Install-WindowsFeature DHCP -IncludeManagementTools`; `netsh dhcp add securitygroups` |
| **Authorize** | Right-click server → **Authorize** | `Add-DhcpServerInDC -DnsName dc01.corp.homelab.local -IPAddress 10.10.10.10` |
| Scope | IPv4 → New Scope → `10.10.10.100–200` /24, lease 8 days | `Add-DhcpServerv4Scope -Name LAB-Workstations -StartRange 10.10.10.100 -EndRange 10.10.10.200 -SubnetMask 255.255.255.0` |
| Exclusion | Address Pool → New Exclusion → `.100–.109` | `Add-DhcpServerv4ExclusionRange -ScopeId 10.10.10.0 -StartRange 10.10.10.100 -EndRange 10.10.10.109` |
| Options 003/006/015 | Scope Options → Router, DNS Servers, DNS Domain Name | `Set-DhcpServerv4OptionValue -ScopeId 10.10.10.0 -Router 10.10.10.10 -DnsServer 10.10.10.10 -DnsDomain corp.homelab.local` |
| Reservation (WS01) | Reservations → New → MAC of WS01 → `10.10.10.150` | `Add-DhcpServerv4Reservation -ScopeId 10.10.10.0 -IPAddress 10.10.10.150 -ClientId <MAC> -Name ws01` |

> ⚠️ **Forgetting to authorize** is the classic mistake: the service runs, the scope is active, and no client ever gets an address. Authorisation stops rogue DHCP servers on a domain network.
>
> ⚠️ **Option 006 must be the DC**, never the router or 8.8.8.8.

**Done when:** `Test-LabHealth.ps1` shows DNS, DHCP authorised, SRV record and internet resolution all OK.

---

## Phase 4 – Clients and domain join

### 4.1 Install Windows 11 Enterprise

During setup, when asked how to set up the device, choose **Set up for work or school → Sign-in options → Domain join instead**, and create a local account (e.g. `labadmin`). This avoids signing in with a Microsoft account.

### 4.2 Confirm DHCP before joining

```powershell
ipconfig /all        # expect 10.10.10.1xx, gateway 10.10.10.10, DNS 10.10.10.10, suffix corp.homelab.local
nltest /dsgetdc:corp.homelab.local      # must return DC01 - if not, fix DNS before joining
Test-NetConnection dc01.corp.homelab.local -Port 389
```

**Why:** domain join works by DNS-looking-up a DC for the domain. If `nltest` fails, the join will fail with "An Active Directory Domain Controller for the domain could not be contacted".

### 4.3 Rename and join

| GUI | PowerShell (on the client, as local admin) |
|---|---|
| Settings → System → About → **Rename this PC** → `WS01`, restart | `Rename-Computer -NewName WS01 -Restart` |
| `sysdm.cpl` → Change → Member of Domain → `corp.homelab.local` → CORP\Administrator | `Add-Computer -DomainName corp.homelab.local -Credential CORP\Administrator -OUPath "OU=Computers,OU=Head Office,OU=Corp,DC=corp,DC=homelab,DC=local" -Restart` |

For WS02 use `-OUPath "OU=Computers,OU=Store-0421,OU=Stores,OU=Corp,DC=corp,DC=homelab,DC=local"` (the OUs exist after Phase 5, so either build Phase 5 first or move the computer afterwards):

```powershell
Get-ADComputer WS02 | Move-ADObject -TargetPath "OU=Computers,OU=Store-0421,OU=Stores,OU=Corp,DC=corp,DC=homelab,DC=local"
```

**Why the OU matters:** computers left in the default `Computers` container can't have GPOs linked to them — it's a container, not an OU. Optionally redirect new joins with `redircmp "OU=Computers,OU=Head Office,OU=Corp,DC=corp,DC=homelab,DC=local"`.

Then get WS01's MAC (`Get-NetAdapter`) and re-run `03-Configure-NetworkServices.ps1 -WS01Mac <MAC> -SkipNat` for the reservation; on WS01 run `ipconfig /release; ipconfig /renew` → `10.10.10.150`.

**Done when:** both clients show in the right OUs in ADUC, `nltest /sc_verify:corp.homelab.local` succeeds on each, WS01 has `10.10.10.150`.

### 4.4 Admin tools on WS01 (how a service desk actually works)

Service desk staff reset passwords from their own PC with RSAT, not by logging on to a DC. On WS01 (elevated):

```powershell
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
Add-WindowsCapability -Online -Name Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0
```

After Phase 5, sign in as `arjun.mehta` (GS-IT-Support) and confirm you can reset and unlock a store user, but **can't** delete users or edit GPOs. That's delegation working.

---

## Phase 5 – OUs, groups, users, file share

Run [`04-Build-Directory.ps1`](../scripts/04-Build-Directory.ps1), then [`New-BulkUsers.ps1`](../scripts/New-BulkUsers.ps1).

| Task | GUI | PowerShell |
|---|---|---|
| OU | ADUC → right-click → New → Organizational Unit (keep "Protect from accidental deletion" ticked) | `New-ADOrganizationalUnit -Name Stores -Path "OU=Corp,DC=corp,DC=homelab,DC=local"` |
| Group | ADUC → Groups OU → New → Group → Global, Security | `New-ADGroup -Name GS-Finance-RW -GroupScope Global -GroupCategory Security -Path "OU=Groups,OU=Corp,..."` |
| User | ADUC → New → User → set password, tick "User must change password at next logon" | `New-ADUser ... -ChangePasswordAtLogon $true` (see `New-BulkUsers.ps1`) |
| Add to group | User → Member Of → Add | `Add-ADGroupMember GS-Finance-RW -Members priya.sharma` |
| Delegate reset/unlock | Corp OU → **Delegate Control** → GS-IT-Support → "Reset user passwords and force password change at next logon" | `dsacls` lines in `04-Build-Directory.ps1` |
| Folder NTFS | Folder → Properties → Security → Advanced → Disable inheritance → add groups | `icacls` lines in `04-Build-Directory.ps1` |
| Share | Folder → Properties → Sharing → Advanced Sharing → Permissions | `New-SmbShare -Name Departments -Path C:\Shares\Departments -ChangeAccess 'Authenticated Users' -FolderEnumerationMode AccessBased` |

```powershell
.\New-BulkUsers.ps1 -CsvPath .\users.csv -WhatIf    # dry run first, always
.\New-BulkUsers.ps1 -CsvPath .\users.csv
```

**Why OUs vs groups:** OUs are for *applying policy and delegating admin*; groups are for *granting access*. A cashier's account sits in the Store-0421 OU (so store GPOs apply) and in GS-Store0421-Users (so the store drive maps).

**Why share = broad, NTFS = specific:** when accessing over the network, the **most restrictive** of share and NTFS wins. Keeping the share wide open to authenticated users and doing everything in NTFS means one place to check. Scenario 8 shows what happens when someone tightens the share.

> ⚠️ Never grant permissions to individual users on the file system. When they leave, you get orphaned SIDs ("S-1-5-21-…") on your ACLs.

Test access-based enumeration: sign in to WS01 as `ethan.walker` and open `\\DC01\Departments` — he should only see Merchandising and Public.

**Done when:** 19 users exist in the right OUs with groups, the share is visible, and a Finance user can open Finance while a Merchandising user can't see it.

---

## Phase 6 – Group Policy

### 6.1 How Group Policy decides what wins

| Concept | Meaning |
|---|---|
| **LSDOU** | Processing order: **L**ocal → **S**ite → **D**omain → **O**U (parent → child). Later wins, so the OU closest to the object wins a conflict. |
| **Link** | A GPO does nothing until linked to a site, domain or OU. One GPO can be linked in many places. |
| **Link order** | Within one OU, link order 1 has the highest precedence. |
| **Enforced** | An enforced link can't be overridden by child OUs and ignores Block Inheritance. |
| **Block inheritance** | Stops parent GPOs flowing down to this OU (except Enforced ones). |
| **Security filtering** | Who the GPO applies to. Default: Authenticated Users. Needs both **Read** and **Apply group policy**. |
| **Delegation / Read** | Since MS16-072, user GPOs are read in the computer's context, so **Domain Computers** (or Authenticated Users) must keep **Read** even when you filter by a user group. |
| **WMI filtering** | A query evaluated on the client, e.g. apply only to Windows 11 workstations. |
| **User vs Computer** | Computer settings apply to *computer objects* in the linked OU at startup; user settings apply to *user objects* in the linked OU at sign-in. A user setting in a GPO linked to a computers-only OU does nothing (unless loopback processing is used). |

Refresh: every 90 minutes ± 30 on clients; `gpupdate /force` to trigger. Some settings (drive maps, folder redirection) need a sign-out.

### 6.2 Password and lockout policy

| Setting | Default Domain Policy | PSO-IT-Admins (fine-grained) |
|---|---|---|
| Minimum length | 12 | 15 |
| History | 24 | 24 |
| Maximum age | 90 days | 60 days |
| Lockout threshold | 5 attempts | 3 attempts |
| Lockout duration / reset counter | 15 min / 15 min | 30 min / 30 min |

- **GUI:** GPMC → Default Domain Policy → Edit → Computer Configuration → Policies → Windows Settings → Security Settings → Account Policies.
- **Why only there:** domain password policy is read from GPOs **linked at the domain root**. The same settings in an OU-linked GPO do nothing for domain accounts.
- **Fine-grained (GUI):** Active Directory Administrative Center → System → Password Settings Container → New → Password Settings → apply to GS-IT-Admins.
- **PowerShell:** [`05-Configure-GroupPolicy.ps1`](../scripts/05-Configure-GroupPolicy.ps1) creates the PSO and verifies both.

```powershell
Get-ADDefaultDomainPasswordPolicy
Get-ADUserResultantPasswordPolicy adm.emily.chen     # shows PSO-IT-Admins
Get-ADUserResultantPasswordPolicy jacob.wilson       # empty = domain policy applies
```

### 6.3 Store restrictions

Created by `05-Configure-GroupPolicy.ps1`, linked to the **Stores** OU:

| GPO | Path in the editor |
|---|---|
| U-Stores-Desktop-Lockdown | User Config → Policies → Admin Templates → Control Panel → **Prohibit access to Control Panel and PC settings** = Enabled |
| | User Config → Policies → Admin Templates → Desktop → Desktop → **Desktop Wallpaper** = `\\corp.homelab.local\NETLOGON\store-wallpaper.jpg`, Fill |
| C-Stores-Removable-Storage | Computer Config → Policies → Admin Templates → System → Removable Storage Access → **All Removable Storage classes: Deny all access** = Enabled |

Copy any JPG to `C:\Windows\SYSVOL\sysvol\corp.homelab.local\scripts\store-wallpaper.jpg` first (that folder is the NETLOGON share, readable by all users).

### 6.4 Drive mappings with Group Policy Preferences (GUI only)

GPMC → **U-Drive-Mappings** → Edit → User Configuration → **Preferences** → Windows Settings → **Drive Maps** → New → Mapped Drive:

| Letter | Location | Label | Item-level targeting (Common tab) |
|---|---|---|---|
| F: | `\\DC01\Departments\Finance` | Finance | Security Group **GS-Finance-RW** OR **GS-Finance-RO** |
| H: | `\\DC01\Departments\HR` | HR | Security Group GS-HR-RW |
| M: | `\\DC01\Departments\Merchandising` | Merchandising | Security Group GS-Merch-RW |
| S: | `\\DC01\Departments\StoreOps` | Store Ops | GS-StoreOps-RW OR GS-Store0421-Users OR GS-Store0587-Users |
| P: | `\\DC01\Departments\Public` | Public | none (everyone) |

For each: Action = **Update**, "Reconnect" ticked, then Common tab → tick **Item-level targeting** → Targeting → New Item → Security Group.

**Why GPP + targeting instead of one GPO per department:** one GPO, one place to look, and access follows group membership automatically. **Why "Update" not "Create":** Update fixes a drive that the user deleted or that points to the wrong path; Create only acts if the drive doesn't exist.

### 6.5 WMI filter (example)

GPMC → WMI Filters → New → `Windows 11 workstations`:

```sql
SELECT * FROM Win32_OperatingSystem WHERE Version LIKE "10.0.2%" AND ProductType = "1"
```

`ProductType 1` = workstation (2 = DC, 3 = server). Windows 11 builds are 22000+. Attach it to C-Stores-Removable-Storage (Scope tab → WMI Filtering). WMI filters cost logon time — use them sparingly.

### 6.6 Verify on a client

```powershell
gpupdate /force
gpresult /r                              # applied / filtered GPOs, group membership
gpresult /h C:\Temp\gp.html /f           # full HTML report
rsop.msc                                 # GUI view of the resultant settings
```

Sign in to WS02 as `jacob.wilson`: Control Panel blocked, store wallpaper, USB storage denied, S: and P: mapped. Sign in to WS01 as `priya.sharma`: no restrictions, F: and P: mapped.

**Done when:** both tests above pass and `gpresult /r` lists the expected GPOs.

---

## Phase 7 – Onboarding and offboarding automation

```powershell
# Onboarding: always dry-run first
.\New-BulkUsers.ps1 -CsvPath .\users.csv -WhatIf
.\New-BulkUsers.ps1 -CsvPath .\users.csv

# Offboarding
.\Invoke-UserOffboarding.ps1 -Identity liam.carter -Ticket RITM0010042 -WhatIf
.\Invoke-UserOffboarding.ps1 -Identity liam.carter -Ticket RITM0010042
Get-ADUser liam.carter -Properties Description, MemberOf, Enabled | Select Enabled, Description, DistinguishedName, MemberOf
```

Test the edge cases so you can talk about them in an interview: a user that already exists (skipped), a bad OU path (logged as an error), a group that doesn't exist (warning), running offboarding twice.

**Done when:** onboarding creates all users with a clean log, offboarding moves a test user to Disabled Users with groups recorded in the log.

---

## Phase 8 – Break/fix scenarios

Each scenario in [/tickets](../tickets) has a **"How this scenario was reproduced"** section. Workflow for each one:

1. Run `Test-LabHealth.ps1` — confirm a clean baseline.
2. Break it exactly as the ticket describes.
3. Diagnose from the user's side first (what they see), then admin tools.
4. Fix, verify, run `Test-LabHealth.ps1` again.
5. Update the ticket's work notes with the real output and timestamps.

---

## Optional phases

| Phase | Outline |
|---|---|
| FS01 member server | New Server 2022 VM, static `10.10.10.11`, join domain, move the Departments share with Robocopy (`/COPYALL /MIR`), update GPP drive paths, add File Server Resource Manager quotas |
| DC02 | Static `10.10.10.12`, DNS → `10.10.10.10`, `Install-ADDSDomainController`, then `repadmin /replsummary`, `repadmin /showrepl`. Add DC02 as DHCP option 006 secondary. Consider DHCP failover. |
| Entra Cloud Sync | M365 trial / developer tenant → add a routable UPN suffix in AD Domains and Trusts (e.g. your verified tenant domain), change test users' UPN → install the Cloud Sync provisioning agent on DC01 → scope to Head Office OU → verify users appear in Entra ID |
| ITSM tool | ServiceNow Personal Developer Instance or osTicket; enter INC0010001–9 and the KBs, link each KB to its incident |
| Windows LAPS | `Update-LapsADSchema`, GPO to back up local admin passwords to AD — directly relevant to Scenario 7 |
