// =============================================================
// ArnotOnboarding — Page05_AccountSetup.cs  v1.0.0.0
// Description: Account setup — Steps 4-7. Checkboxes, radio buttons,
//              conditional fields, auto-suggested username.
// =============================================================
using System;
using System.Drawing;
using System.Windows.Forms;
using ArnotOnboarding.Managers;
using ArnotOnboarding.Models;
using ArnotOnboarding.Theme;

namespace ArnotOnboarding.Views.WizardPages
{
    public class Page05_AccountSetup : WizardPageBase
    {
        public override string PageTitle => "Account Setup";

        private CheckBox    _chkNewAccount;
        private CheckBox    _chkModifyExisting;
        private RadioButton _rbCopyYes;
        private RadioButton _rbCopyNo;
        private TextBox     _txtCopyFrom;
        private Label       _lblCopyFrom;
        private TextBox     _txtUsername;
        private TextBox     _txtPassword;
        private RadioButton _rbForceChangeYes;
        private RadioButton _rbForceChangeNo;

        public Page05_AccountSetup()
        {
            int y = START_Y;

            // Step 4 — Account type (checkboxes — both can be true)
            Controls.Add(MakeSectionHeader("Step 4 — Account Type", y)); y += 32;
            _chkNewAccount      = MakeCheckBox("Create new account",    y); y += 30;
            _chkModifyExisting  = MakeCheckBox("Modify existing account", y); y += ROW_HEIGHT;

            Controls.Add(MakeDivider(y)); y += 16;

            // Step 5 — Copy permissions (radio — Yes/No)
            Controls.Add(MakeSectionHeader("Step 5 — Copy Permissions from Existing User", y)); y += 32;
            _rbCopyYes = MakeRadioButton("Yes — copy from existing user", y); y += 30;
            _rbCopyNo  = MakeRadioButton("No",                            y); y += ROW_HEIGHT;

            // Step 6 — Copy from which user (conditional)
            _lblCopyFrom = MakeLabel("Copy From User", y);
            _txtCopyFrom = MakeTextBox(y); y += ROW_HEIGHT;

            Controls.Add(MakeDivider(y)); y += 16;

            // Step 7 — Domain credentials
            Controls.Add(MakeSectionHeader("Step 7 — Domain Credentials", y)); y += 32;

            Controls.Add(MakeLabel("Domain Username", y));
            _txtUsername = MakeTextBox(y); y += ROW_HEIGHT;
            Controls.Add(MakeNoteLabel("Auto-suggested from employee name. Edit as needed.", y - 14));

            Controls.Add(MakeLabel("Initial Password", y));
            _txtPassword = MakeTextBox(y); y += ROW_HEIGHT;
            Controls.Add(MakeNoteLabel("Plain text — this is an internal handoff form.", y - 14));

            Controls.Add(MakeLabel("Force Password Change", y));
            _rbForceChangeYes = MakeRadioButton("Yes — prompt on first login", y); y += 30;
            _rbForceChangeNo  = MakeRadioButton("No",                           y); y += ROW_HEIGHT;

            Controls.AddRange(new Control[]
            {
                _chkNewAccount, _chkModifyExisting,
                _rbCopyYes, _rbCopyNo, _lblCopyFrom, _txtCopyFrom,
                _txtUsername, _txtPassword,
                _rbForceChangeYes, _rbForceChangeNo
            });

            // Show/hide copy-from field based on radio selection
            _rbCopyYes.CheckedChanged += (s, e) => {
                bool show = _rbCopyYes.Checked;
                _lblCopyFrom.Visible = show;
                _txtCopyFrom.Visible = show;
                RaiseDataChanged();
            };
            _rbCopyNo.CheckedChanged += (s, e) => RaiseDataChanged();

            // Default state
            _rbCopyNo.Checked        = true;
            _lblCopyFrom.Visible     = false;
            _txtCopyFrom.Visible     = false;
            _rbForceChangeYes.Checked = true;
        }

        /// <summary>Called by WizardView when employee name changes on page 1 to refresh username suggestion.</summary>
        public void SuggestUsername(string firstName, string lastName)
        {
            if (_loading) return;
            if (string.IsNullOrWhiteSpace(_txtUsername.Text))
            {
                _txtUsername.Text = AppSettingsManager.Instance.Customer.GenerateUsername(firstName, lastName);
            }
        }

        public override void LoadData(OnboardingRecord r)
        {
            _loading = true;
            _chkNewAccount.Checked     = r.NewAccount;
            _chkModifyExisting.Checked = r.ModifyExistingAccount;
            _rbCopyYes.Checked         = r.CopyPermissions;
            _rbCopyNo.Checked          = !r.CopyPermissions;
            _txtCopyFrom.Text          = r.CopyFromUser;
            _lblCopyFrom.Visible       = r.CopyPermissions;
            _txtCopyFrom.Visible       = r.CopyPermissions;

            if (string.IsNullOrEmpty(r.DomainUsername))
                _txtUsername.Text = AppSettingsManager.Instance.Customer.GenerateUsername(r.EmployeeFirstName, r.EmployeeLastName);
            else
                _txtUsername.Text = r.DomainUsername;

            _txtPassword.Text          = r.InitialPassword;
            _rbForceChangeYes.Checked  = r.ForcePasswordChange;
            _rbForceChangeNo.Checked   = !r.ForcePasswordChange;
            _loading = false;
        }

        public override OnboardingRecord SaveData(OnboardingRecord r)
        {
            r.NewAccount            = _chkNewAccount.Checked;
            r.ModifyExistingAccount = _chkModifyExisting.Checked;
            r.CopyPermissions       = _rbCopyYes.Checked;
            r.CopyFromUser          = _txtCopyFrom.Text.Trim();
            r.DomainUsername        = _txtUsername.Text.Trim();
            r.InitialPassword       = _txtPassword.Text.Trim();
            r.ForcePasswordChange   = _rbForceChangeYes.Checked;
            return r;
        }
    }
}
