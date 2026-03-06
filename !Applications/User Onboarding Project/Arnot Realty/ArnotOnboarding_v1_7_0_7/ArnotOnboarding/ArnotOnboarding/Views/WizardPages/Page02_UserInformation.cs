// =============================================================
// ArnotOnboarding — Page02_UserInformation.cs  v1.3.0.0
// Form Section 2: User Information
// =============================================================
using System;
using System.Windows.Forms;
using ArnotOnboarding.Managers;
using ArnotOnboarding.Models;
using ArnotOnboarding.Theme;

namespace ArnotOnboarding.Views.WizardPages
{
    public class Page02_UserInformation : WizardPageBase
    {
        public override string PageTitle => "User Information";

        private TextBox _txtEmployeeName;
        private TextBox _txtEmail;
        private TextBox _txtPhoneNumber;
        private TextBox _txtExtension;
        private TextBox _txtDeskLocation;
        private TextBox _txtJobTitle;
        private TextBox _txtDepartment;
        private TextBox _txtPrimaryComputerName;
        private bool    _emailManuallyEdited = false;

        // Raised when computer name changes so WizardView can push to Page06
        public event EventHandler<string> ComputerNameChanged;

        public Page02_UserInformation()
        {
            int y = START_Y;
            Controls.Add(MakeSectionHeader("Section 2 — User Information", y)); y += 32;

            Controls.Add(MakeLabel("Employee Name", y));
            _txtEmployeeName = MakeTextBox(y);
            _txtEmployeeName.TextChanged += OnEmployeeNameChanged;
            Controls.Add(_txtEmployeeName); y += ROW_HEIGHT;

            Controls.Add(MakeLabel("Email", y));
            _txtEmail = MakeTextBox(y);
            _txtEmail.Font      = AppFonts.Mono;
            _txtEmail.ForeColor = AppColors.BrandBlue;
            _txtEmail.TextChanged += (s, e) => { _emailManuallyEdited = true; RaiseDataChanged(); };
            Controls.Add(_txtEmail); y += ROW_HEIGHT;

            Controls.Add(MakeLabel("Phone Number", y));
            _txtPhoneNumber = MakeTextBox(y);
            Controls.Add(_txtPhoneNumber); y += ROW_HEIGHT;

            Controls.Add(MakeLabel("Extension", y));
            _txtExtension = MakeTextBox(y, 120);
            Controls.Add(_txtExtension); y += ROW_HEIGHT;

            Controls.Add(MakeLabel("Desk Location", y));
            _txtDeskLocation = MakeTextBox(y);
            Controls.Add(_txtDeskLocation); y += ROW_HEIGHT;

            Controls.Add(MakeLabel("Job Title", y));
            _txtJobTitle = MakeTextBox(y);
            Controls.Add(_txtJobTitle); y += ROW_HEIGHT;

            Controls.Add(MakeLabel("Department", y));
            _txtDepartment = MakeTextBox(y);
            Controls.Add(_txtDepartment); y += ROW_HEIGHT;

            Controls.Add(MakeLabel("Primary Computer Name", y));
            _txtPrimaryComputerName = MakeTextBox(y);
            _txtPrimaryComputerName.TextChanged += (s, e) =>
            {
                RaiseDataChanged();
                if (!_loading) ComputerNameChanged?.Invoke(this, _txtPrimaryComputerName.Text);
            };
            Controls.Add(_txtPrimaryComputerName);
        }

        private void OnEmployeeNameChanged(object sender, EventArgs e)
        {
            RaiseDataChanged();
            if (_emailManuallyEdited || _loading) return;
            // Auto-suggest email from full name typed as "First Last"
            string[] parts = _txtEmployeeName.Text.Trim().Split(new char[]{' '}, 2, System.StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length == 2)
            {
                string gen = AppSettingsManager.Instance.Customer.GenerateEmail(parts[0], parts[1]);
                if (!string.IsNullOrEmpty(gen)) _txtEmail.Text = gen;
            }
        }

        /// <summary>Called by WizardView when Page06 computer name changes.</summary>
        public void SyncComputerName(string name)
        {
            if (_loading) return;
            _loading = true;
            _txtPrimaryComputerName.Text = name;
            _loading = false;
        }

        public override void LoadData(OnboardingRecord r)
        {
            _loading = true;
            _emailManuallyEdited        = r.EmailOverridden;
            _txtEmployeeName.Text       = r.FullName;
            _txtEmail.Text              = r.EmailAddress;
            _txtPhoneNumber.Text        = r.WorkPhone;
            _txtExtension.Text          = r.Extension;
            _txtDeskLocation.Text       = r.OfficeLocation;
            _txtJobTitle.Text           = r.Title;
            _txtDepartment.Text         = r.Department;
            _txtPrimaryComputerName.Text = r.PrimaryComputerName;
            _loading = false;
        }

        public override OnboardingRecord SaveData(OnboardingRecord r)
        {
            // Parse "First Last" into separate fields
            string[] parts = _txtEmployeeName.Text.Trim().Split(new char[]{' '}, 2, System.StringSplitOptions.RemoveEmptyEntries);
            r.EmployeeFirstName  = parts.Length > 0 ? parts[0] : string.Empty;
            r.EmployeeLastName   = parts.Length > 1 ? parts[1] : string.Empty;
            r.EmailAddress       = _txtEmail.Text.Trim();
            r.EmailOverridden    = _emailManuallyEdited;
            r.WorkPhone          = _txtPhoneNumber.Text.Trim();
            r.Extension          = _txtExtension.Text.Trim();
            r.OfficeLocation     = _txtDeskLocation.Text.Trim();
            r.Title              = _txtJobTitle.Text.Trim();
            r.Department         = _txtDepartment.Text.Trim();
            r.PrimaryComputerName  = _txtPrimaryComputerName.Text.Trim();
            r.ExistingComputerName = r.PrimaryComputerName; // keep in sync with Q12
            return r;
        }

        public override string Validate()
        {
            if (string.IsNullOrWhiteSpace(_txtEmployeeName.Text))
                return "Please enter the employee name.";
            return null;
        }
    }
}
