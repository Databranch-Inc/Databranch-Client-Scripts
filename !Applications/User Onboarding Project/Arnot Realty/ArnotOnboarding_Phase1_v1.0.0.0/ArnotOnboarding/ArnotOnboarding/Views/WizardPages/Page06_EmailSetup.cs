// =============================================================
// ArnotOnboarding — Page06_EmailSetup.cs  v1.0.0.0
// Description: Email setup — Step 8. Email address synced from
//              page 3, distribution lists, shared mailboxes, delegates.
// =============================================================
using System;
using System.Windows.Forms;
using ArnotOnboarding.Models;
using ArnotOnboarding.Theme;

namespace ArnotOnboarding.Views.WizardPages
{
    public class Page06_EmailSetup : WizardPageBase
    {
        public override string PageTitle => "Email Setup";

        private TextBox     _txtEmail;
        private TextBox     _txtEmailPassword;
        private TextBox     _txtLicenseType;
        private RadioButton _rbNewMailbox;
        private RadioButton _rbExistingMailbox;
        private TextBox     _txtDistribLists;
        private TextBox     _txtSharedMailboxes;
        private TextBox     _txtDelegates;

        public Page06_EmailSetup()
        {
            int y = START_Y;
            Controls.Add(MakeSectionHeader("Step 8 — Email Account", y)); y += 32;

            Controls.Add(MakeLabel("Email Address", y));
            _txtEmail = MakeTextBox(y);
            _txtEmail.Font      = Theme.AppFonts.Mono;
            _txtEmail.ForeColor = Theme.AppColors.BrandBlue;
            _txtEmail.ReadOnly  = true;
            _txtEmail.BackColor = Theme.AppColors.SurfaceRaised;
            Controls.Add(MakeNoteLabel("Synced from User Information page. Change it there.", y + 28));
            y += ROW_HEIGHT + 14;

            Controls.Add(MakeLabel("Email Password", y));
            _txtEmailPassword = MakeTextBox(y); y += ROW_HEIGHT;

            Controls.Add(MakeLabel("License Type", y));
            _txtLicenseType = MakeTextBox(y);
            Controls.Add(MakeNoteLabel("e.g. Microsoft 365 Business Basic", y + 28));
            y += ROW_HEIGHT + 14;

            Controls.Add(MakeLabel("Mailbox", y));
            _rbNewMailbox      = MakeRadioButton("New mailbox",      y); y += 28;
            _rbExistingMailbox = MakeRadioButton("Existing mailbox", y); y += ROW_HEIGHT;
            _rbNewMailbox.Checked = true;

            Controls.Add(MakeDivider(y)); y += 16;
            Controls.Add(MakeSectionHeader("Distribution Lists & Shared Mailboxes", y)); y += 32;

            Controls.Add(MakeLabel("Distribution Lists", y));
            _txtDistribLists = MakeMultiLineTextBox(y, 70);
            Controls.Add(MakeNoteLabel("One email address per line", y + 72));
            y += 90;

            Controls.Add(MakeLabel("Shared Mailboxes", y));
            _txtSharedMailboxes = MakeMultiLineTextBox(y, 70);
            Controls.Add(MakeNoteLabel("One mailbox per line", y + 72));
            y += 90;

            Controls.Add(MakeLabel("Calendar Delegates", y));
            _txtDelegates = MakeMultiLineTextBox(y, 70);
            Controls.Add(MakeNoteLabel("One name or email per line", y + 72));

            Controls.AddRange(new Control[]
            {
                _txtEmail, _txtEmailPassword, _txtLicenseType,
                _rbNewMailbox, _rbExistingMailbox,
                _txtDistribLists, _txtSharedMailboxes, _txtDelegates
            });
        }

        /// <summary>Called by WizardView when email changes on page 3 to keep in sync.</summary>
        public void SyncEmail(string email)
        {
            _txtEmail.Text = email;
        }

        public override void LoadData(OnboardingRecord r)
        {
            _loading = true;
            _txtEmail.Text             = r.EmailAddress;
            _txtEmailPassword.Text     = r.EmailPassword;
            _txtLicenseType.Text       = r.EmailLicenseType;
            _rbNewMailbox.Checked      = r.NewMailbox;
            _rbExistingMailbox.Checked = !r.NewMailbox;
            _txtDistribLists.Text      = r.DistributionLists;
            _txtSharedMailboxes.Text   = r.SharedMailboxes;
            _txtDelegates.Text         = r.CalendarDelegates;
            _loading = false;
        }

        public override OnboardingRecord SaveData(OnboardingRecord r)
        {
            r.EmailPassword    = _txtEmailPassword.Text.Trim();
            r.EmailLicenseType = _txtLicenseType.Text.Trim();
            r.NewMailbox       = _rbNewMailbox.Checked;
            r.DistributionLists = _txtDistribLists.Text.Trim();
            r.SharedMailboxes  = _txtSharedMailboxes.Text.Trim();
            r.CalendarDelegates = _txtDelegates.Text.Trim();
            return r;
        }
    }
}
