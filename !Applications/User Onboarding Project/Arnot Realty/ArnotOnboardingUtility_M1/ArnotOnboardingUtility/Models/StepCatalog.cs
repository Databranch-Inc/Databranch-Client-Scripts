// =============================================================
// ArnotOnboardingUtility — Models/StepCatalog.cs
// Version    : 1.0.0.0
// Author     : Sam Kirsch / Databranch
// Created    : 2026-02-28
// Modified   : 2026-02-28
// Description: Static factory that returns the ordered, resolved
//              list of StepDefinitions for a given OnboardingRecord.
//              Conditional steps are evaluated here and either
//              included or excluded. Index values are assigned
//              after resolution so progress numbers are stable.
// =============================================================
using System.Collections.Generic;
using System.Linq;

namespace ArnotOnboardingUtility.Models
{
    public static class StepCatalog
    {
        // ── Account key constants for otherAccounts dictionary ────────
        private const string KEY_BSN      = "Breach Secure Now (IT)";
        private const string KEY_DUO      = "DUO 2FA Security (IT)";
        private const string KEY_FILECLOUD = "FileCloud (IT) - Enforce 2FA";
        private const string KEY_LASTPASS = "LastPass (IT) - Enforce 2FA";
        private const string KEY_VOIP     = "RockIT VOIP (IT)";
        private const string KEY_VAST     = "Vast 2 (IT)";
        private const string KEY_VPN      = "VPN access (IT) \u2013 Duo required"; // en-dash from JSON

        /// <summary>
        /// Returns the fully resolved, index-assigned step list for the given record.
        /// Conditional steps absent from the JSON are filtered out before indexing.
        /// </summary>
        public static List<StepDefinition> Build(OnboardingRecord r)
        {
            var raw = r.IsKioskUser ? BuildKiosk(r) : BuildDesktop(r);

            // Assign sequential indices to visible steps only
            int idx = 0;
            foreach (var step in raw.Where(s => s.IsVisible))
                step.Index = idx++;

            return raw.Where(s => s.IsVisible).ToList();
        }

        // ══════════════════════════════════════════════════════════════
        //  DESKTOP USER STEP CATALOG
        // ══════════════════════════════════════════════════════════════
        private static List<StepDefinition> BuildDesktop(OnboardingRecord r)
        {
            bool hasMailbox  = r.SharedMailboxes21 || r.DistributionLists22 || r.EmailAliases25;

            return new List<StepDefinition>
            {
                // ── Account Setup Phase ────────────────────────────────

                new StepDefinition
                {
                    StepLabel = "1",
                    Title     = "Create Active Directory User Account",
                    Type      = StepType.Automated,
                    Phase     = "Account Setup",
                    ScriptResourceName = "New-ArnotADUser.ps1",
                    GuidanceText =
                        "Creates the AD user object in the arc.local domain with all attributes from " +
                        "the onboarding record. The temp password is set as-is; force-change-at-login " +
                        "is left OFF so you can log in as the user during PC setup. HR's " +
                        "force-change flag is applied during the User Call phase.\n\n" +
                        "Review the data summary below before running. If a disabled account already " +
                        "exists for this username, delete it first.",
                    IsVisible = true
                },

                new StepDefinition
                {
                    StepLabel = "1a",
                    Title     = "Assign AD Group Memberships",
                    Type      = StepType.Automated,
                    Phase     = "Account Setup",
                    ScriptResourceName = "Set-ArnotADGroups.ps1",
                    GuidanceText =
                        "Assigns all drive-mapping groups (R, Q, K, S), shared-folder AD groups, " +
                        "FileCloud-users, Duo groups, and Local Administrators based on the " +
                        "onboarding record flags. Review group assignments in the data summary " +
                        "before running.",
                    IsVisible = true
                },

                new StepDefinition
                {
                    StepLabel = "1b",
                    Title     = "Email Requestor — AD Account Active",
                    Type      = StepType.Manual,
                    Phase     = "Account Setup",
                    GuidanceText =
                        "Send an email to the requestor notifying them that the AD account is active " +
                        "and the email address is live in MailProtector. This is required so Arnot " +
                        "can assign any application licenses they manage independently.\n\n" +
                        "To: {RequestorEmail}\n" +
                        "Subject: IT Setup Update — {EmployeeFirstName} {EmployeeLastName}\n\n" +
                        "Body: The Active Directory account for {EmployeeFirstName} {EmployeeLastName} " +
                        "is now active. Username: {DomainUsername}@arnotrealty.com. " +
                        "Please assign any application licenses that require an active AD/email account.",
                    IsVisible = true
                },

                new StepDefinition
                {
                    StepLabel = "2",
                    Title     = "Connect to Exchange Online (MFA)",
                    Type      = StepType.Automated,
                    Phase     = "Account Setup",
                    ScriptResourceName = "Connect-ArnotExchangeOnline.ps1",
                    GuidanceText =
                        "Establishes an authenticated Exchange Online session. Running this script " +
                        "opens an interactive MFA browser window — complete sign-in there. " +
                        "The session persists in the PowerShell runspace for all subsequent " +
                        "Exchange steps (3, 3b, 3c) without prompting again.",
                    IsVisible = r.AccountMS365
                },

                new StepDefinition
                {
                    StepLabel = "3",
                    Title     = "Create Microsoft 365 User",
                    Type      = StepType.Automated,
                    Phase     = "Account Setup",
                    ScriptResourceName = "New-Arnot365User.ps1",
                    GuidanceText =
                        "Creates the Microsoft 365 user account and assigns the appropriate license. " +
                        "The M365 temp password is set with force-change-at-login ON (correct for " +
                        "cloud accounts — different from domain). No admin roles are assigned.",
                    IsVisible = r.AccountMS365
                },

                new StepDefinition
                {
                    StepLabel = "3a",
                    Title     = "Sync to MailProtector",
                    Type      = StepType.Manual,
                    Phase     = "Account Setup",
                    GuidanceText =
                        "1. Log into the MailProtector admin portal.\n" +
                        "2. Navigate to the arnotrealty.com domain.\n" +
                        "3. Run a manual domain sync.\n" +
                        "4. Wait 10–15 minutes for Microsoft to fully provision the Exchange mailbox " +
                        "   before running Step 3b. The calendar script will fail if the mailbox " +
                        "   is not yet accessible.",
                    IsVisible = r.AccountMS365
                },

                new StepDefinition
                {
                    StepLabel = "3b",
                    Title     = "Set Peter Dugo Calendar Permissions",
                    Type      = StepType.Automated,
                    Phase     = "Account Setup",
                    ScriptResourceName = "Set-ArnotCalendarPermissions.ps1",
                    GuidanceText =
                        "Adds pdugo@arnotrealty.com as a Reviewer on the new user's calendar. " +
                        "This script is a rewrite of the legacy Add_PDUGO script — it accepts " +
                        "the user email as a parameter and requires no manual input.\n\n" +
                        "Prerequisite: Exchange Online session must be active (Step 2) and the " +
                        "mailbox must exist (Step 3a — allow 10–15 min).",
                    IsVisible = r.AccountMS365 && r.RunCalendarScript
                },

                new StepDefinition
                {
                    StepLabel = "3c",
                    Title     = "Configure Mailbox Access",
                    Type      = StepType.Automated,
                    Phase     = "Account Setup",
                    ScriptResourceName = "Set-ArnotMailboxAccess.ps1",
                    GuidanceText =
                        "Adds the user to shared mailboxes, distribution lists, and email aliases " +
                        "as specified in the onboarding record. Empty lists are skipped gracefully.",
                    IsVisible = hasMailbox && r.AccountMS365
                },

                new StepDefinition
                {
                    StepLabel = "4",
                    Title     = "Breach Secure Now",
                    Type      = StepType.Manual,
                    Phase     = "Account Setup",
                    GuidanceText =
                        "1. Open Microsoft Entra (Azure AD).\n" +
                        "2. Navigate to Groups → BSN-Employees.\n" +
                        "3. Add the new user as a member.\n" +
                        "4. Confirm the account syncs to the Breach Secure Now portal (may take 15–30 min).\n" +
                        "5. Verify the BSN Welcome Email arrives in the user's mailbox during PC setup.",
                    IsVisible = r.OtherAccountRequired(KEY_BSN)
                },

                new StepDefinition
                {
                    StepLabel = "5",
                    Title     = "Duo MFA Setup",
                    Type      = StepType.Manual,
                    Phase     = "Account Setup",
                    GuidanceText =
                        "AD group memberships (Duo_ArnotComputers_Users, etc.) were already applied " +
                        "in Step 1a. This step handles the Duo Admin Portal configuration.\n\n" +
                        "1. Log into the Arnot Duo Admin Portal.\n" +
                        "2. Navigate to Users — locate the new user (search by AD username).\n" +
                        "3. The user will appear as 'Not Enrolled' — this is expected before device setup.\n" +
                        "4. Set the user to Bypass mode so setup can proceed before the employee's start date.\n" +
                        "5. During the User Call phase, disable Bypass and have the user enroll their device.",
                    IsVisible = r.OtherAccountRequired(KEY_DUO)
                },

                new StepDefinition
                {
                    StepLabel = "6",
                    Title     = "FileCloud Account",
                    Type      = StepType.Manual,
                    Phase     = "Account Setup",
                    GuidanceText =
                        "The FileCloud-users AD group was assigned in Step 1a. This step provisions " +
                        "the portal account.\n\n" +
                        "1. Log into the FileCloud Admin Portal.\n" +
                        "2. Navigate to Users → Import from Active Directory.\n" +
                        "3. Search for {DomainUsername} and import.\n" +
                        "4. Verify the account appears in the user list with correct name and email.",
                    IsVisible = r.OtherAccountRequired(KEY_FILECLOUD)
                },

                new StepDefinition
                {
                    StepLabel = "7",
                    Title     = "LastPass Account",
                    Type      = StepType.Manual,
                    Phase     = "Account Setup",
                    GuidanceText =
                        "1. Log into the LastPass Business MSP portal under the Arnot Realty tenant.\n" +
                        "2. Navigate to Users → Add User.\n" +
                        "3. Enter: Email = {EmailAddress}, Name = {EmployeeFirstName} {EmployeeLastName}.\n" +
                        "4. Send activation email.\n" +
                        "5. MFA policy is site-wide — no additional per-user configuration required.\n" +
                        "6. During PC setup, install the LastPass universal installer and set the " +
                        "   15-minute session timeout policy.",
                    IsVisible = r.OtherAccountRequired(KEY_LASTPASS)
                },

                new StepDefinition
                {
                    StepLabel = "8",
                    Title     = "RockIT VOIP",
                    Type      = StepType.Manual,
                    Phase     = "Account Setup",
                    GuidanceText =
                        "1. Log into the RockIT VOIP admin portal.\n" +
                        "2. Locate the phone to assign (see data summary for model/number).\n" +
                        "3. If reassigning an existing phone: update user association and reset voicemail PIN.\n" +
                        "4. If provisioning a new phone: follow the New Device workflow.\n" +
                        "5. Set voicemail greeting.\n" +
                        "6. Send Welcome Email from the portal to {EmailAddress}.",
                    IsVisible = r.OtherAccountRequired(KEY_VOIP) || r.PhoneIssued
                },

                new StepDefinition
                {
                    StepLabel = "9",
                    Title     = "VAST2 Camera Access",
                    Type      = StepType.Manual,
                    Phase     = "Account Setup",
                    GuidanceText =
                        "1. RDP to AXXX-VIVOTEK-21.\n" +
                        "2. Open the VAST2 application.\n" +
                        "3. Navigate to User Management → Add User.\n" +
                        "4. Look up {DomainUsername} from Active Directory.\n" +
                        "5. Set role to Customize with view-only camera permissions per runbook.\n" +
                        "6. Test login with domain credentials before closing.",
                    IsVisible = r.OtherAccountRequired(KEY_VAST)
                },

                new StepDefinition
                {
                    StepLabel = "10",
                    Title     = "VPN Access",
                    Type      = StepType.Manual,
                    Phase     = "Account Setup",
                    GuidanceText =
                        "The Duo_Arnot-VPN_Users AD group was assigned in Step 1a.\n\n" +
                        "1. Confirm the Duo_Arnot-VPN_Users group appears in the user's AD group list.\n" +
                        "2. The ARNOT-VPN RasPhone application deploys automatically via GPO after domain join.\n" +
                        "3. VPN testing must be performed from outside the Arnot network with Duo active " +
                        "   (not Bypass). Test this during or after the User Call phase.",
                    IsVisible = r.OtherAccountRequired(KEY_VPN)
                },

                // ── PC Setup Phase ─────────────────────────────────────

                new StepDefinition
                {
                    StepLabel = "11",
                    Title     = "PC Hardware Review",
                    Type      = StepType.Manual,
                    Phase     = "PC Setup",
                    GuidanceText =
                        "Review the hardware configuration below. For new or factory-reset PCs:\n" +
                        "  • Image with the Databranch Standard Windows 10 image.\n" +
                        "  • Install base in-house applications via Automate.\n" +
                        "  • Install Office 365 Apps.\n" +
                        "  • Apply all Windows patches.\n" +
                        "  • Prepare for domain join (Step 12).\n\n" +
                        "For existing PCs with no factory reset, verify hardware condition and " +
                        "confirm all drivers are current before proceeding.",
                    IsVisible = true
                },

                new StepDefinition
                {
                    StepLabel = "12",
                    Title     = "PC Name & Domain Join",
                    Type      = StepType.Manual,
                    Phase     = "PC Setup",
                    GuidanceText =
                        "1. Rename the PC per the naming convention in the data summary.\n" +
                        "2. Join the arc.local domain.\n" +
                        "3. Log in with the Databranch admin account to cache credentials on the device.\n" +
                        "4. Verify the machine is reachable via ScreenConnect.\n" +
                        "5. If relocating the computer, confirm physical move to the new location.",
                    IsVisible = true
                },

                new StepDefinition
                {
                    StepLabel = "13",
                    Title     = "Docking Station & Monitor Setup",
                    Type      = StepType.Manual,
                    Phase     = "PC Setup",
                    GuidanceText =
                        "1. Verify the desk is configured per the hardware summary below.\n" +
                        "2. Connect docking station and monitors using the connector types listed.\n" +
                        "3. Test all display outputs — confirm resolution and arrangement.\n" +
                        "4. Run Windows Update after all hardware is connected.\n" +
                        "5. Run Lenovo Driver Update (if applicable) with all hardware attached.",
                    IsVisible = true
                },

                new StepDefinition
                {
                    StepLabel = "14",
                    Title     = "Application Installation",
                    Type      = StepType.Manual,
                    Phase     = "PC Setup",
                    GuidanceText =
                        "Install all applications listed in the data summary.\n\n" +
                        "Key notes per application:\n" +
                        "  • Acrobat Pro: invite email from Admin Console handles licensing — " +
                        "    do not enter a serial number.\n" +
                        "  • LastPass: deploy universal installer; configure 15-minute session logout.\n" +
                        "  • Office 365 Apps: sign into each app with O365 credentials " +
                        "    (select 'This App Only' — not organization-wide).\n" +
                        "  • VAST2 Client: install newest client, test login with domain credentials.\n" +
                        "  • Duo Security: install desktop app; confirm Bypass mode is active for now.",
                    IsVisible = true
                },

                new StepDefinition
                {
                    StepLabel = "15",
                    Title     = "Printing & Scanning Setup",
                    Type      = StepType.Manual,
                    Phase     = "PC Setup",
                    GuidanceText =
                        "Printers:\n" +
                        "  • Main Office and Stillwater printers deploy via GPO automatically after domain join.\n" +
                        "  • Set the default printer manually per user preference.\n\n" +
                        "Scanning:\n" +
                        "  • Create the user scan folder: D:\\Company Data\\Scans\\{DomainUsername} on ARC-FS1.\n" +
                        "  • For Xerox MFD: configure Scan to Folder workflow per runbook (template available).\n" +
                        "  • For HP MFD: configure using HP Embedded Web Server.\n" +
                        "  • Test a scan to the folder and confirm file arrives.",
                    IsVisible = r.PrintersRequired || r.ScanToFolder
                },

                new StepDefinition
                {
                    StepLabel = "16",
                    Title     = "File / Share Access & Email Verification",
                    Type      = StepType.Manual,
                    Phase     = "PC Setup",
                    GuidanceText =
                        "File / Share Access:\n" +
                        "  • Verify all mapped drives listed below are accessible and contain expected content.\n" +
                        "  • Test access to each shared subfolder on R: and Q: listed below.\n\n" +
                        "Email & Calendar:\n" +
                        "  • Open Outlook and sign in with {Ms365Username}.\n" +
                        "  • Confirm shared mailboxes appear below the main mailbox in the folder pane.\n" +
                        "  • Send a test email to a distribution list and verify delivery.\n" +
                        "  • Add Conference Room and Board Room calendars per runbook.\n" +
                        "  • Confirm any email aliases are routing correctly.",
                    IsVisible = true
                }
            };
        }

        // ══════════════════════════════════════════════════════════════
        //  KIOSK USER STEP CATALOG
        // ══════════════════════════════════════════════════════════════
        private static List<StepDefinition> BuildKiosk(OnboardingRecord r)
        {
            bool hasMailbox = r.SharedMailboxes21 || r.DistributionLists22 || r.EmailAliases25;

            return new List<StepDefinition>
            {
                new StepDefinition
                {
                    StepLabel = "1",
                    Title     = "Email Requestor — O365 Account Pending",
                    Type      = StepType.Manual,
                    Phase     = "Account Setup",
                    GuidanceText =
                        "Kiosk users do not receive an AD account. Notify the requestor that " +
                        "the Microsoft 365 Kiosk account setup is in progress.\n\n" +
                        "To: {RequestorEmail}\n" +
                        "Subject: IT Setup Update — {EmployeeFirstName} {EmployeeLastName}\n\n" +
                        "Body: The Microsoft 365 Kiosk account for {EmployeeFirstName} {EmployeeLastName} " +
                        "is being configured. You will receive a follow-up when the account is ready.",
                    IsVisible = true
                },

                new StepDefinition
                {
                    StepLabel = "2",
                    Title     = "Connect to Exchange Online (MFA)",
                    Type      = StepType.Automated,
                    Phase     = "Account Setup",
                    ScriptResourceName = "Connect-ArnotExchangeOnline.ps1",
                    GuidanceText =
                        "Establishes an authenticated Exchange Online session via interactive MFA. " +
                        "The session persists for all subsequent Exchange steps.",
                    IsVisible = true
                },

                new StepDefinition
                {
                    StepLabel = "3",
                    Title     = "Create Microsoft 365 Kiosk User",
                    Type      = StepType.Automated,
                    Phase     = "Account Setup",
                    ScriptResourceName = "New-Arnot365User.ps1",
                    GuidanceText =
                        "Creates the Microsoft 365 user account with the Kiosk license. " +
                        "Force-change-at-login is enabled. No admin roles are assigned.",
                    IsVisible = true
                },

                new StepDefinition
                {
                    StepLabel = "3a",
                    Title     = "Sync to MailProtector",
                    Type      = StepType.Manual,
                    Phase     = "Account Setup",
                    GuidanceText =
                        "1. Log into the MailProtector admin portal.\n" +
                        "2. Navigate to the arnotrealty.com domain.\n" +
                        "3. Run a manual domain sync.\n" +
                        "4. Wait 10–15 minutes before running Step 3b.",
                    IsVisible = true
                },

                new StepDefinition
                {
                    StepLabel = "3b",
                    Title     = "Set Peter Dugo Calendar Permissions",
                    Type      = StepType.Automated,
                    Phase     = "Account Setup",
                    ScriptResourceName = "Set-ArnotCalendarPermissions.ps1",
                    GuidanceText =
                        "Adds pdugo@arnotrealty.com as Reviewer on the new user's calendar. " +
                        "Requires an active Exchange Online session (Step 2) and an existing mailbox.",
                    IsVisible = r.RunCalendarScript
                },

                new StepDefinition
                {
                    StepLabel = "3c",
                    Title     = "Configure Mailbox Access",
                    Type      = StepType.Automated,
                    Phase     = "Account Setup",
                    ScriptResourceName = "Set-ArnotMailboxAccess.ps1",
                    GuidanceText =
                        "Adds the user to shared mailboxes, distribution lists, and email aliases " +
                        "as specified in the onboarding record.",
                    IsVisible = hasMailbox
                },

                new StepDefinition
                {
                    StepLabel = "4",
                    Title     = "Breach Secure Now",
                    Type      = StepType.Manual,
                    Phase     = "Account Setup",
                    GuidanceText =
                        "All Kiosk users require BSN enrollment.\n\n" +
                        "1. Open Microsoft Entra.\n" +
                        "2. Add the user to BSN-Employees AND Everyone groups.\n" +
                        "3. Confirm account syncs to the BSN portal.\n" +
                        "4. Verify the BSN Welcome Email arrives.",
                    IsVisible = true // Always shown for Kiosk
                },

                new StepDefinition
                {
                    StepLabel = "5",
                    Title     = "iPad / Device Provisioning",
                    Type      = StepType.Manual,
                    Phase     = "Account Setup",
                    GuidanceText =
                        "1. Log into the Meraki MDM portal.\n" +
                        "2. Locate the iPad assigned to this user (see data summary).\n" +
                        "3. Assign the device to {EmailAddress} in Meraki.\n" +
                        "4. Confirm device enrollment and policy application.\n" +
                        "5. Test O365 app sign-in on the iPad with the new credentials.",
                    IsVisible = r.IPadIssued
                }
            };
        }
    }
}
