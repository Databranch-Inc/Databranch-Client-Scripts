// =============================================================
// ArnotOnboarding — CustomerProfile.cs
// Version    : 1.0.0.0
// Author     : Sam Kirsch
// Company    : Databranch
// Created    : 2026-02-22
// Modified   : 2026-02-22
// Description: Customer-specific configuration. All Arnot Realty-specific
//              values live here so that adapting the app for another
//              client means replacing this file and recompiling.
//              Loaded from customer-profile.json in %AppData%.
// =============================================================

using System.Collections.Generic;

namespace ArnotOnboarding.Models
{
    /// <summary>Defines the format rule used to auto-generate email addresses.</summary>
    public enum EmailFormat
    {
        FirstInitialLastName,   // jsmith@domain.com
        FirstDotLast,           // john.smith@domain.com
        FirstLast               // johnsmith@domain.com
    }

    public class CustomerProfile
    {
        public string SchemaVersion  { get; set; } = "1.0";
        public string CustomerName   { get; set; } = "Arnot Realty";
        public string EmailDomain    { get; set; } = "arnotrealty.com";
        public EmailFormat EmailFormat { get; set; } = EmailFormat.FirstInitialLastName;

        /// <summary>
        /// MdmNote is the contextual message shown on the mobile device page
        /// next to the MDM enrollment question.
        /// </summary>
        public string MdmNote { get; set; } =
            "Christina usually handles MDM enrollment. " +
            "Databranch engineer involvement only under special circumstances.";

        /// <summary>Applications listed on wizard page 7 (checkboxes).</summary>
        public List<string> ApplicationsList { get; set; } = new List<string>
        {
            "Microsoft Office 365",
            "Microsoft Teams",
            "Adobe Acrobat",
            "QuickBooks",
            "Dropbox",
            "Ironworks",
            "Chrome",
            "Other (see notes)"
        };

        /// <summary>Options for Step 15c VPN type radio buttons.</summary>
        public List<string> VpnTypes { get; set; } = new List<string>
        {
            "GlobalProtect",
            "Cisco AnyConnect",
            "SonicWall",
            "Other"
        };

        /// <summary>Monitor type options for Step 14.</summary>
        public List<string> MonitorTypes { get; set; } = new List<string>
        {
            "Standard (1080p)",
            "Widescreen (1440p)",
            "Ultrawide",
            "Laptop Screen Only"
        };

        /// <summary>Step 16 — Remote desktop option checkboxes.</summary>
        public List<string> RemoteDesktopOptions { get; set; } = new List<string>
        {
            "Windows Remote Desktop",
            "ScreenConnect / ConnectWise",
            "Other"
        };

        /// <summary>Step 17a — Software access checkboxes.</summary>
        public List<string> SoftwareAccessList { get; set; } = new List<string>
        {
            "Property Management System",
            "Accounting Software",
            "CRM",
            "Document Management",
            "Other"
        };

        /// <summary>Step 18a — Access rights checkboxes.</summary>
        public List<string> AccessRightsList { get; set; } = new List<string>
        {
            "Standard User",
            "Local Admin",
            "Domain Admin",
            "HR Files",
            "Executive Drive",
            "Financial Records",
            "Other"
        };

        /// <summary>Step 19 — Additional access checkboxes.</summary>
        public List<string> AdditionalAccessList { get; set; } = new List<string>
        {
            "VPN Access",
            "Remote Desktop",
            "SharePoint",
            "OneDrive",
            "Other"
        };

        /// <summary>Step 20 — Security option checkboxes.</summary>
        public List<string> SecurityOptionsList { get; set; } = new List<string>
        {
            "Multi-Factor Authentication",
            "Password Manager",
            "Encrypted Drive",
            "Other"
        };

        /// <summary>Voicemail setup options for the phone page.</summary>
        public List<string> VoicemailSetupOptions { get; set; } = new List<string>
        {
            "Set up voicemail greeting",
            "Forward voicemail to email",
            "Transfer existing voicemail box"
        };

        /// <summary>
        /// Generates an email address from first/last name according to this profile's EmailFormat.
        /// Returns empty string if either name part is missing.
        /// </summary>
        public string GenerateEmail(string firstName, string lastName)
        {
            if (string.IsNullOrWhiteSpace(firstName) || string.IsNullOrWhiteSpace(lastName))
                return string.Empty;

            firstName = firstName.Trim().ToLower();
            lastName  = lastName.Trim().ToLower();

            string local;
            switch (EmailFormat)
            {
                case EmailFormat.FirstDotLast:
                    local = $"{firstName}.{lastName}";
                    break;
                case EmailFormat.FirstLast:
                    local = $"{firstName}{lastName}";
                    break;
                case EmailFormat.FirstInitialLastName:
                default:
                    local = $"{firstName[0]}{lastName}";
                    break;
            }

            return $"{local}@{EmailDomain}";
        }

        /// <summary>
        /// Returns a suggested domain username using the same logic as email generation
        /// but without the @ domain part.
        /// </summary>
        public string GenerateUsername(string firstName, string lastName)
        {
            if (string.IsNullOrWhiteSpace(firstName) || string.IsNullOrWhiteSpace(lastName))
                return string.Empty;

            firstName = firstName.Trim().ToLower();
            lastName  = lastName.Trim().ToLower();

            switch (EmailFormat)
            {
                case EmailFormat.FirstDotLast:   return $"{firstName}.{lastName}";
                case EmailFormat.FirstLast:      return $"{firstName}{lastName}";
                default:                         return $"{firstName[0]}{lastName}";
            }
        }
    }
}
