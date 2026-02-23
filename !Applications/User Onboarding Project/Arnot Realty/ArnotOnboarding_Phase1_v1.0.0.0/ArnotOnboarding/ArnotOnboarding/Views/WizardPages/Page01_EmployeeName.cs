// =============================================================
// ArnotOnboarding — Page01_EmployeeName.cs  v1.0.0.0
// Description: Wizard page 1 — Employee name entry.
//              Creates the draft record on first Next press.
// =============================================================
using System;
using System.Drawing;
using System.Windows.Forms;
using ArnotOnboarding.Models;
using ArnotOnboarding.Theme;

namespace ArnotOnboarding.Views.WizardPages
{
    public class Page01_EmployeeName : WizardPageBase
    {
        public override string PageTitle => "Employee Name";

        private TextBox _txtFirstName;
        private TextBox _txtLastName;
        private Label   _lblEmailPreview;

        public Page01_EmployeeName()
        {
            int y = START_Y;

            var hdr = MakeSectionHeader("New Employee Details", y);
            y += 32;

            var lblFirst = MakeLabel("First Name *", y);
            _txtFirstName = MakeTextBox(y);
            _txtFirstName.TextChanged += UpdateEmailPreview;
            y += ROW_HEIGHT;

            var lblLast = MakeLabel("Last Name *", y);
            _txtLastName = MakeTextBox(y);
            _txtLastName.TextChanged += UpdateEmailPreview;
            y += ROW_HEIGHT;

            var lblPreview = MakeLabel("Email preview", y);
            _lblEmailPreview = new Label
            {
                Location  = new Point(COL_FIELD_X, y + 4),
                Size      = new Size(COL_FIELD_W, 22),
                Font      = AppFonts.Mono,
                ForeColor = AppColors.TextDim,
                BackColor = Color.Transparent,
                Text      = "(enter name above)"
            };
            y += ROW_HEIGHT;

            Controls.AddRange(new Control[]
                { hdr, lblFirst, _txtFirstName, lblLast, _txtLastName, lblPreview, _lblEmailPreview });
        }

        private void UpdateEmailPreview(object sender, EventArgs e)
        {
            RaiseDataChanged();
            var profile = Managers.AppSettingsManager.Instance.Customer;
            string preview = profile.GenerateEmail(_txtFirstName.Text, _txtLastName.Text);
            _lblEmailPreview.Text      = string.IsNullOrEmpty(preview) ? "(enter name above)" : preview;
            _lblEmailPreview.ForeColor = string.IsNullOrEmpty(preview) ? AppColors.TextDim : AppColors.BrandBlue;
        }

        public override void LoadData(OnboardingRecord r)
        {
            _loading = true;
            _txtFirstName.Text = r.EmployeeFirstName;
            _txtLastName.Text  = r.EmployeeLastName;
            _loading = false;
            UpdateEmailPreview(null, EventArgs.Empty);
        }

        public override OnboardingRecord SaveData(OnboardingRecord r)
        {
            r.EmployeeFirstName = _txtFirstName.Text.Trim();
            r.EmployeeLastName  = _txtLastName.Text.Trim();
            return r;
        }

        public override string Validate()
        {
            if (string.IsNullOrWhiteSpace(_txtFirstName.Text))
                return "Please enter the employee's first name.";
            if (string.IsNullOrWhiteSpace(_txtLastName.Text))
                return "Please enter the employee's last name.";
            return null;
        }
    }
}
