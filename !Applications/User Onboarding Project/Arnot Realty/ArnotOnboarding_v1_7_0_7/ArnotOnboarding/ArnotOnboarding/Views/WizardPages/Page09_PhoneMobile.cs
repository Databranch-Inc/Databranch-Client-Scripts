// =============================================================
// ArnotOnboarding — Page09_PhoneMobile.cs  v1.3.0.0
// Form Steps 26-31: Office Telephone & Mobile Devices
// Steps 29, 30, 30a, 30b, 31 are all individual lines with their own fields.
// =============================================================
using System.Drawing;
using System.Windows.Forms;
using ArnotOnboarding.Models;
using ArnotOnboarding.Theme;

namespace ArnotOnboarding.Views.WizardPages
{
    public class Page09_PhoneMobile : WizardPageBase
    {
        public override string PageTitle => "Office Phone & Mobile (Steps 26-31)";

        // Step 26
        private Panel _grp26; private RadioButton _rb26Existing, _rb26New;
        // Step 27
        private Panel _grp27; private RadioButton _rb27Yes, _rb27No;
        private TextBox _txt27Location;
        // Step 28
        private Panel _grp28; private RadioButton _rb28Yes, _rb28No;
        // Step 29
        private TextBox _txt29VmPin;
        // Step 30 — Phone
        private Panel _grp30Phone; private RadioButton _rb30PhoneYes, _rb30PhoneNo;
        private TextBox _txt30PhoneModel, _txt30PhoneNumber;
        private Panel _grp30PhoneNew; private RadioButton _rb30PhoneExisting, _rb30PhoneNew;
        // Step 30 — iPad
        private Panel _grp30iPad; private RadioButton _rb30iPadYes, _rb30iPadNo;
        private TextBox _txt30iPadModel, _txt30iPadNumber;
        private Panel _grp30iPadNew; private RadioButton _rb30iPadExisting, _rb30iPadNew;
        // Step 31 — Databranch note only

        public Page09_PhoneMobile()
        {
            int y = START_Y;
            Controls.Add(MakeSectionHeader("Office Telephone (Steps 26-29)", y)); y += 32;

            // Step 26
            Controls.Add(MakeLabel("26) Office phone\nExisting or New?", y));
            _grp26 = MakeRPanel(y, "Existing", "New", out _rb26Existing, out _rb26New); Controls.Add(_grp26); y += ROW_HEIGHT;

            // Step 27
            Controls.Add(MakeLabel("27) Existing phone\nneed to be relocated?", y));
            _grp27 = MakeRPanel(y, "Yes", "No", out _rb27Yes, out _rb27No); Controls.Add(_grp27); y += ROW_HEIGHT;
            Controls.Add(MakeLabel("27a) Current location:", y));
            _txt27Location = MakeTextBox(y); Controls.Add(_txt27Location); y += ROW_HEIGHT;

            // Step 28
            Controls.Add(MakeLabel("28) Extension change\nrequired?", y));
            _grp28 = MakeRPanel(y, "Yes", "No", out _rb28Yes, out _rb28No); Controls.Add(_grp28); y += ROW_HEIGHT;

            // Step 29
            Controls.Add(MakeLabel("29) Temp VM Pin\n(4-digit):", y));
            _txt29VmPin = MakeTextBox(y, 80); Controls.Add(_txt29VmPin); y += ROW_HEIGHT;

            Controls.Add(MakeDivider(y)); y += 12;
            Controls.Add(MakeSectionHeader("Mobile Devices (Steps 30-31)", y)); y += 32;

            // Step 30 — Phone
            Controls.Add(MakeLabel("30) Arnot Realty owned\nphone issued?", y));
            _grp30Phone = MakeRPanel(y, "Yes", "No", out _rb30PhoneYes, out _rb30PhoneNo); Controls.Add(_grp30Phone); y += ROW_HEIGHT;
            Controls.Add(MakeLabel("30a) Phone Model:", y));
            _txt30PhoneModel = MakeTextBox(y, 160); Controls.Add(_txt30PhoneModel);
            Controls.Add(MakeLabel("30a) Phone Number:", y + ROW_HEIGHT));
            _txt30PhoneNumber = MakeTextBox(y + ROW_HEIGHT, 160); Controls.Add(_txt30PhoneNumber); y += ROW_HEIGHT * 2;
            Controls.Add(MakeLabel("30a) Existing or New?", y));
            _grp30PhoneNew = MakeRPanel(y, "Existing", "New", out _rb30PhoneExisting, out _rb30PhoneNew); Controls.Add(_grp30PhoneNew); y += ROW_HEIGHT;

            Controls.Add(MakeDivider(y)); y += 12;

            // Step 30 — iPad
            Controls.Add(MakeLabel("30) Arnot Realty owned\niPad issued?", y));
            _grp30iPad = MakeRPanel(y, "Yes", "No", out _rb30iPadYes, out _rb30iPadNo); Controls.Add(_grp30iPad); y += ROW_HEIGHT;
            Controls.Add(MakeLabel("30b) iPad Model:", y));
            _txt30iPadModel = MakeTextBox(y, 160); Controls.Add(_txt30iPadModel);
            Controls.Add(MakeLabel("30b) Device Number:", y + ROW_HEIGHT));
            _txt30iPadNumber = MakeTextBox(y + ROW_HEIGHT, 160); Controls.Add(_txt30iPadNumber); y += ROW_HEIGHT * 2;
            Controls.Add(MakeLabel("30b) Existing or New?", y));
            _grp30iPadNew = MakeRPanel(y, "Existing", "New", out _rb30iPadExisting, out _rb30iPadNew); Controls.Add(_grp30iPadNew); y += ROW_HEIGHT;

            Controls.Add(MakeDivider(y)); y += 12;

            // Step 31 — Databranch engineer task
            var note31 = new Label
            {
                Text      = "Step 31: Databranch engineer to complete enrollment/assignment to Meraki MDM solution",
                Location  = new Point(COL_FIELD_X, y),
                Size      = new Size(COL_FIELD_W_WIDE, 36),
                Font      = AppFonts.BodySmall,
                ForeColor = AppColors.BrandRedPale,
                BackColor = Color.Transparent
            };
            Controls.Add(note31);
        }

        private Panel MakeRPanel(int y, string l1, string l2, out RadioButton r1, out RadioButton r2)
        {
            var p = new Panel { Location = new Point(COL_FIELD_X, y), Size = new Size(220, 26), BackColor = Color.Transparent };
            r1 = new RadioButton { Text = l1, Location = new Point(0, 2),   Size = new Size(100, 22), BackColor = Color.Transparent, ForeColor = AppColors.TextSecondary, Font = AppFonts.Body };
            r2 = new RadioButton { Text = l2, Location = new Point(110, 2), Size = new Size(100, 22), BackColor = Color.Transparent, ForeColor = AppColors.TextSecondary, Font = AppFonts.Body };
            r2.Checked = true;
            r1.CheckedChanged += (s, e) => RaiseDataChanged();
            r2.CheckedChanged += (s, e) => RaiseDataChanged();
            p.Controls.Add(r1); p.Controls.Add(r2);
            return p;
        }

        public override void LoadData(OnboardingRecord r)
        {
            _loading = true;
            SetR(_rb26Existing, _rb26New,       r.PhoneExisting);
            SetR(_rb27Yes, _rb27No,             r.PhoneRelocate);
            _txt27Location.Text               = r.PhoneCurrentLocation;
            SetR(_rb28Yes, _rb28No,             r.ExtensionChange);
            _txt29VmPin.Text                  = r.VmPin;
            SetR(_rb30PhoneYes, _rb30PhoneNo,   r.PhoneIssued);
            _txt30PhoneModel.Text             = r.PhoneModel;
            _txt30PhoneNumber.Text            = r.PhoneNumber;
            SetR(_rb30PhoneExisting, _rb30PhoneNew, r.PhoneDeviceExisting);
            SetR(_rb30iPadYes, _rb30iPadNo,     r.iPadIssued);
            _txt30iPadModel.Text              = r.iPadModel;
            _txt30iPadNumber.Text             = r.iPadNumber;
            SetR(_rb30iPadExisting, _rb30iPadNew, r.iPadDeviceExisting);
            _loading = false;
        }

        public override OnboardingRecord SaveData(OnboardingRecord r)
        {
            r.PhoneExisting        = _rb26Existing.Checked;
            r.PhoneRelocate        = _rb27Yes.Checked;
            r.PhoneCurrentLocation = _txt27Location.Text.Trim();
            r.ExtensionChange      = _rb28Yes.Checked;
            r.VmPin                = _txt29VmPin.Text.Trim();
            r.PhoneIssued          = _rb30PhoneYes.Checked;
            r.PhoneModel           = _txt30PhoneModel.Text.Trim();
            r.PhoneNumber          = _txt30PhoneNumber.Text.Trim();
            r.PhoneDeviceExisting  = _rb30PhoneExisting.Checked;
            r.iPadIssued           = _rb30iPadYes.Checked;
            r.iPadModel            = _txt30iPadModel.Text.Trim();
            r.iPadNumber           = _txt30iPadNumber.Text.Trim();
            r.iPadDeviceExisting   = _rb30iPadExisting.Checked;
            return r;
        }

        private void SetR(RadioButton r1, RadioButton r2, bool v) { r1.Checked = v; r2.Checked = !v; }
    }
}
