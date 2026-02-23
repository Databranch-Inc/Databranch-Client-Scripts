// =============================================================
// ArnotOnboarding — Page04_RequestorInfo.cs  v1.0.0.0
// Description: Requestor information — pre-filled from saved profile,
//              editable inline with a reset button.
// =============================================================
using System;
using System.Windows.Forms;
using ArnotOnboarding.Managers;
using ArnotOnboarding.Models;
using ArnotOnboarding.Theme;

namespace ArnotOnboarding.Views.WizardPages
{
    public class Page04_RequestorInfo : WizardPageBase
    {
        public override string PageTitle => "Requestor Information";

        private TextBox         _txtName;
        private TextBox         _txtTitle;
        private TextBox         _txtPhone;
        private TextBox         _txtEmail;
        private DateTimePicker  _dtpDate;
        private Button          _btnReset;

        public Page04_RequestorInfo()
        {
            int y = START_Y;
            Controls.Add(MakeSectionHeader("Requestor Details", y)); y += 28;
            Controls.Add(MakeNoteLabel("Pre-filled from your saved profile. Edit here for this request only.", y)); y += 28;

            Controls.Add(MakeLabel("Name", y));
            _txtName = MakeTextBox(y); y += ROW_HEIGHT;

            Controls.Add(MakeLabel("Title", y));
            _txtTitle = MakeTextBox(y); y += ROW_HEIGHT;

            Controls.Add(MakeLabel("Phone", y));
            _txtPhone = MakeTextBox(y); y += ROW_HEIGHT;

            Controls.Add(MakeLabel("Email", y));
            _txtEmail = MakeTextBox(y); y += ROW_HEIGHT;

            Controls.Add(MakeLabel("Request Date", y));
            _dtpDate = MakeDatePicker(y); y += ROW_HEIGHT + 8;

            _btnReset = new Button
            {
                Text     = "↺  Reset to Saved Profile",
                Location = new System.Drawing.Point(COL_FIELD_X, y),
                Size     = new System.Drawing.Size(200, 32)
            };
            ThemeHelper.ApplyButtonStyle(_btnReset, ThemeHelper.ButtonStyle.Ghost);
            _btnReset.Click += OnResetClick;

            Controls.AddRange(new Control[]
                { _txtName, _txtTitle, _txtPhone, _txtEmail, _dtpDate, _btnReset });
        }

        private void OnResetClick(object sender, EventArgs e)
        {
            LoadFromProfile();
            RaiseDataChanged();
        }

        private void LoadFromProfile()
        {
            var p = AppSettingsManager.Instance.Requestor;
            _loading = true;
            _txtName.Text  = p.Name;
            _txtTitle.Text = p.Title;
            _txtPhone.Text = p.Phone;
            _txtEmail.Text = p.Email;
            _loading = false;
        }

        public override void LoadData(OnboardingRecord r)
        {
            _loading = true;
            if (string.IsNullOrEmpty(r.RequestorName))
            {
                // First load — pull from saved profile
                var p = AppSettingsManager.Instance.Requestor;
                _txtName.Text  = p.Name;
                _txtTitle.Text = p.Title;
                _txtPhone.Text = p.Phone;
                _txtEmail.Text = p.Email;
            }
            else
            {
                _txtName.Text  = r.RequestorName;
                _txtTitle.Text = r.RequestorTitle;
                _txtPhone.Text = r.RequestorPhone;
                _txtEmail.Text = r.RequestorEmail;
            }
            _dtpDate.Checked = r.RequestDate.HasValue;
            if (r.RequestDate.HasValue) _dtpDate.Value = r.RequestDate.Value;
            else _dtpDate.Value = DateTime.Today;
            _loading = false;
        }

        public override OnboardingRecord SaveData(OnboardingRecord r)
        {
            r.RequestorName  = _txtName.Text.Trim();
            r.RequestorTitle = _txtTitle.Text.Trim();
            r.RequestorPhone = _txtPhone.Text.Trim();
            r.RequestorEmail = _txtEmail.Text.Trim();
            r.RequestDate    = _dtpDate.Checked ? _dtpDate.Value.Date : (DateTime?)null;
            return r;
        }
    }
}
