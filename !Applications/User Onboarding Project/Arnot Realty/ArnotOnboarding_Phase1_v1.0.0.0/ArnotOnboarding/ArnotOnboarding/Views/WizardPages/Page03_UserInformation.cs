// =============================================================
// ArnotOnboarding — Page03_UserInformation.cs  v1.0.0.0
// Description: User information — auto-populates name from page 1,
//              email from customer profile format, with override.
// =============================================================
using System;
using System.Drawing;
using System.Windows.Forms;
using ArnotOnboarding.Managers;
using ArnotOnboarding.Models;
using ArnotOnboarding.Theme;

namespace ArnotOnboarding.Views.WizardPages
{
    public class Page03_UserInformation : WizardPageBase
    {
        public override string PageTitle => "User Information";

        private TextBox  _txtFirstName;
        private TextBox  _txtLastName;
        private TextBox  _txtTitle;
        private TextBox  _txtDepartment;
        private TextBox  _txtReportsTo;
        private TextBox  _txtOffice;
        private TextBox  _txtWorkPhone;
        private TextBox  _txtCellPhone;
        private TextBox  _txtEmail;
        private CheckBox _chkEmailOverride;

        // Expose email so Page06 can stay in sync
        public string EmailAddress
        {
            get { return _txtEmail.Text.Trim(); }
            set { _txtEmail.Text = value; }
        }

        public Page03_UserInformation()
        {
            int y = START_Y;
            Controls.Add(MakeSectionHeader("Employee Details", y)); y += 32;

            Controls.Add(MakeLabel("First Name", y));
            _txtFirstName = MakeTextBox(y);
            _txtFirstName.TextChanged += OnNameChanged; y += ROW_HEIGHT;

            Controls.Add(MakeLabel("Last Name", y));
            _txtLastName = MakeTextBox(y);
            _txtLastName.TextChanged += OnNameChanged; y += ROW_HEIGHT;

            Controls.Add(MakeLabel("Job Title", y));
            _txtTitle = MakeTextBox(y); y += ROW_HEIGHT;

            Controls.Add(MakeLabel("Department", y));
            _txtDepartment = MakeTextBox(y); y += ROW_HEIGHT;

            Controls.Add(MakeLabel("Reports To", y));
            _txtReportsTo = MakeTextBox(y); y += ROW_HEIGHT;

            Controls.Add(MakeLabel("Office Location", y));
            _txtOffice = MakeTextBox(y); y += ROW_HEIGHT;

            Controls.Add(MakeLabel("Work Phone", y));
            _txtWorkPhone = MakeTextBox(y); y += ROW_HEIGHT;

            Controls.Add(MakeLabel("Cell Phone", y));
            _txtCellPhone = MakeTextBox(y); y += ROW_HEIGHT;

            Controls.Add(MakeDivider(y)); y += 12;
            Controls.Add(MakeSectionHeader("Email Address", y)); y += 32;

            Controls.Add(MakeLabel("Email", y));
            _txtEmail = MakeTextBox(y);
            _txtEmail.ForeColor = AppColors.BrandBlue;
            _txtEmail.Font      = AppFonts.Mono;
            y += ROW_HEIGHT;

            _chkEmailOverride = MakeCheckBox("Override auto-generated email", y); y += ROW_HEIGHT;
            Controls.Add(MakeNoteLabel("Email is auto-generated from name. Check above to type a custom address.", y - ROW_HEIGHT + 28));

            Controls.AddRange(new Control[]
            {
                _txtFirstName, _txtLastName, _txtTitle, _txtDepartment,
                _txtReportsTo, _txtOffice, _txtWorkPhone, _txtCellPhone,
                _txtEmail, _chkEmailOverride
            });

            // Email override toggle
            _chkEmailOverride.CheckedChanged += (s, e) => {
                _txtEmail.ReadOnly  = !_chkEmailOverride.Checked;
                _txtEmail.BackColor = _chkEmailOverride.Checked
                    ? AppColors.SurfaceVoid : AppColors.SurfaceRaised;
                RaiseDataChanged();
            };

            _txtEmail.ReadOnly  = true;
            _txtEmail.BackColor = AppColors.SurfaceRaised;
        }

        private void OnNameChanged(object sender, EventArgs e)
        {
            RaiseDataChanged();
            if (_chkEmailOverride.Checked) return; // Don't override manual entry
            var profile = AppSettingsManager.Instance.Customer;
            string generated = profile.GenerateEmail(_txtFirstName.Text, _txtLastName.Text);
            if (!string.IsNullOrEmpty(generated))
                _txtEmail.Text = generated;
        }

        public override void LoadData(OnboardingRecord r)
        {
            _loading = true;
            _txtFirstName.Text         = r.EmployeeFirstName;
            _txtLastName.Text          = r.EmployeeLastName;
            _txtTitle.Text             = r.Title;
            _txtDepartment.Text        = r.Department;
            _txtReportsTo.Text         = r.DirectReportsTo;
            _txtOffice.Text            = r.OfficeLocation;
            _txtWorkPhone.Text         = r.WorkPhone;
            _txtCellPhone.Text         = r.CellPhone;
            _txtEmail.Text             = r.EmailAddress;
            _chkEmailOverride.Checked  = r.EmailOverridden;
            _txtEmail.ReadOnly         = !r.EmailOverridden;
            _txtEmail.BackColor        = r.EmailOverridden ? AppColors.SurfaceVoid : AppColors.SurfaceRaised;
            _loading = false;
        }

        public override OnboardingRecord SaveData(OnboardingRecord r)
        {
            r.EmployeeFirstName = _txtFirstName.Text.Trim();
            r.EmployeeLastName  = _txtLastName.Text.Trim();
            r.Title             = _txtTitle.Text.Trim();
            r.Department        = _txtDepartment.Text.Trim();
            r.DirectReportsTo   = _txtReportsTo.Text.Trim();
            r.OfficeLocation    = _txtOffice.Text.Trim();
            r.WorkPhone         = _txtWorkPhone.Text.Trim();
            r.CellPhone         = _txtCellPhone.Text.Trim();
            r.EmailAddress      = _txtEmail.Text.Trim();
            r.EmailOverridden   = _chkEmailOverride.Checked;
            return r;
        }
    }
}
