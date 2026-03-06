// =============================================================
// ArnotOnboarding — Page03_RequestorInfo.cs  v1.3.0.0
// Form Section 3: Requestor Information
// =============================================================
using System;
using System.Windows.Forms;
using ArnotOnboarding.Managers;
using ArnotOnboarding.Models;
using ArnotOnboarding.Theme;

namespace ArnotOnboarding.Views.WizardPages
{
    public class Page03_RequestorInfo : WizardPageBase
    {
        public override string PageTitle => "Requestor Information";

        private TextBox _txtRequestorName;
        private TextBox _txtRequestorEmail;
        private TextBox _txtRequestorPhone;
        private TextBox _txtRequestorExtension;
        private Button  _btnReset;

        public Page03_RequestorInfo()
        {
            int y = START_Y;
            Controls.Add(MakeSectionHeader("Section 3 — Requestor Information", y)); y += 28;
            Controls.Add(MakeNoteLabel("Pre-filled from your saved profile (My Information). Edit here for this request only.", y)); y += 28;

            Controls.Add(MakeLabel("3a) Requestor Name", y));
            _txtRequestorName = MakeTextBox(y);
            Controls.Add(_txtRequestorName); y += ROW_HEIGHT;

            Controls.Add(MakeLabel("3b) Requestor Email", y));
            _txtRequestorEmail = MakeTextBox(y);
            Controls.Add(_txtRequestorEmail); y += ROW_HEIGHT;

            Controls.Add(MakeLabel("3c) Requestor Phone", y));
            _txtRequestorPhone = MakeTextBox(y);
            Controls.Add(_txtRequestorPhone); y += ROW_HEIGHT;

            Controls.Add(MakeLabel("3d) Requestor Extension", y));
            _txtRequestorExtension = MakeTextBox(y, 120);
            Controls.Add(_txtRequestorExtension); y += ROW_HEIGHT + 8;

            _btnReset = new Button
            {
                Text     = "↺  Reset to Saved Profile",
                Location = new System.Drawing.Point(COL_FIELD_X, y),
                Size     = new System.Drawing.Size(200, 32)
            };
            ThemeHelper.ApplyButtonStyle(_btnReset, ThemeHelper.ButtonStyle.Ghost);
            _btnReset.Click += (s, e) => { LoadFromProfile(); RaiseDataChanged(); };
            Controls.Add(_btnReset);
        }

        private void LoadFromProfile()
        {
            _loading = true;
            var p = AppSettingsManager.Instance.Requestor;
            _txtRequestorName.Text      = p.Name;
            _txtRequestorEmail.Text     = p.Email;
            _txtRequestorPhone.Text     = p.Phone;
            _txtRequestorExtension.Text = p.Extension;
            _loading = false;
        }

        public override void LoadData(OnboardingRecord r)
        {
            _loading = true;
            if (string.IsNullOrEmpty(r.RequestorName))
                LoadFromProfile();
            else
            {
                _txtRequestorName.Text      = r.RequestorName;
                _txtRequestorEmail.Text     = r.RequestorEmail;
                _txtRequestorPhone.Text     = r.RequestorPhone;
                _txtRequestorExtension.Text = r.RequestorExtension;
            }
            _loading = false;
        }

        public override OnboardingRecord SaveData(OnboardingRecord r)
        {
            r.RequestorName      = _txtRequestorName.Text.Trim();
            r.RequestorEmail     = _txtRequestorEmail.Text.Trim();
            r.RequestorPhone     = _txtRequestorPhone.Text.Trim();
            r.RequestorExtension = _txtRequestorExtension.Text.Trim();
            return r;
        }
    }
}
