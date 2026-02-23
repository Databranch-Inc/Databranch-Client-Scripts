// =============================================================
// ArnotOnboarding — Page12_PhoneMobile.cs  v1.0.0.0
// Description: Office phone & mobile device — Steps 21-31.
//              MDM note pulled from CustomerProfile.
// =============================================================
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;
using ArnotOnboarding.Managers;
using ArnotOnboarding.Models;
using ArnotOnboarding.Theme;

namespace ArnotOnboarding.Views.WizardPages
{
    public class Page12_PhoneMobile : WizardPageBase
    {
        public override string PageTitle => "Phone & Mobile Device";

        private CheckBox            _chkDeskPhone;
        private Panel               _phonePanel;
        private TextBox             _txtExtension;
        private TextBox             _txtPhoneModel;
        private List<CheckBox>      _chkVoicemail = new List<CheckBox>();

        private TextBox             _txtMobileType;
        private TextBox             _txtMobileNumber;
        private TextBox             _txtMobileCarrier;
        private RadioButton         _rbMdmYes;
        private RadioButton         _rbMdmNo;
        private TextBox             _txtMdmNotes;

        public Page12_PhoneMobile()
        {
            int y = START_Y;
            var customer = AppSettingsManager.Instance.Customer;

            // ── Office Telephone ─────────────────────────────────────
            Controls.Add(MakeSectionHeader("Steps 21-26 — Office Telephone", y)); y += 32;

            Controls.Add(MakeLabel("Desk Phone Required", y));
            _chkDeskPhone = MakeCheckBox("Yes — set up a desk phone", y); y += ROW_HEIGHT;
            Controls.Add(_chkDeskPhone);

            // Detail panel for phone options (shown when checked)
            _phonePanel = new Panel
            {
                Location  = new Point(COL_LABEL_X, y),
                Size      = new Size(COL_LABEL_W + COL_FIELD_W + 40, 220),
                BackColor = AppColors.SurfaceCard,
                Visible   = false
            };

            int py = 8;
            var lblExt   = MakeLabel("Extension",   py); lblExt.Location = new Point(COL_LABEL_X, py + 4);
            var txtExt   = MakeTextBox(py); _txtExtension = txtExt;
            py += ROW_HEIGHT;

            var lblModel = MakeLabel("Phone Model", py); lblModel.Location = new Point(COL_LABEL_X, py + 4);
            var txtModel = MakeTextBox(py); _txtPhoneModel = txtModel;
            py += ROW_HEIGHT;

            var lblVm = new Label { Text = "Voicemail Setup", Font = AppFonts.LabelBold, ForeColor = AppColors.TextSecondary, BackColor = Color.Transparent, Location = new Point(COL_LABEL_X, py + 4), Size = new Size(COL_LABEL_W, 24), TextAlign = ContentAlignment.MiddleRight };
            py += 8;
            foreach (string opt in customer.VoicemailSetupOptions)
            {
                var cb = MakeCheckBox(opt, py);
                _chkVoicemail.Add(cb);
                _phonePanel.Controls.Add(cb);
                py += 28;
            }

            _phonePanel.Controls.AddRange(new Control[] { lblExt, _txtExtension, lblModel, _txtPhoneModel, lblVm });
            Controls.Add(_phonePanel);
            y += 230;

            Controls.Add(MakeDivider(y)); y += 16;

            // ── Mobile Device ─────────────────────────────────────────
            Controls.Add(MakeSectionHeader("Steps 27-31 — Mobile Device", y)); y += 32;

            Controls.Add(MakeLabel("Device Type", y));
            _txtMobileType = MakeTextBox(y);
            Controls.Add(MakeNoteLabel("e.g. iPhone 15 Pro, Samsung Galaxy S24", y + 28));
            y += ROW_HEIGHT + 14;

            Controls.Add(MakeLabel("Mobile Number", y));
            _txtMobileNumber = MakeTextBox(y); y += ROW_HEIGHT;

            Controls.Add(MakeLabel("Carrier", y));
            _txtMobileCarrier = MakeTextBox(y); y += ROW_HEIGHT;

            Controls.Add(MakeLabel("MDM Enrollment", y));
            _rbMdmYes = MakeRadioButton("Yes", y); y += 28;
            _rbMdmNo  = MakeRadioButton("No",  y); y += ROW_HEIGHT;
            _rbMdmNo.Checked = true;

            // MDM note from customer profile
            string mdmNote = customer.MdmNote;
            if (!string.IsNullOrEmpty(mdmNote))
            {
                var noteBox = new Label
                {
                    Text      = "ℹ  " + mdmNote,
                    Location  = new Point(COL_FIELD_X, y),
                    Size      = new Size(COL_FIELD_W_WIDE, 48),
                    Font      = AppFonts.Caption,
                    ForeColor = AppColors.TextDim,
                    BackColor = AppColors.StatusInfoBg,
                    Padding   = new Padding(8, 6, 8, 6)
                };
                Controls.Add(noteBox);
                y += 58;
            }

            Controls.Add(MakeLabel("MDM Notes", y));
            _txtMdmNotes = MakeMultiLineTextBox(y, 56); y += 70;

            Controls.AddRange(new Control[]
                { _txtMobileType, _txtMobileNumber, _txtMobileCarrier,
                  _rbMdmYes, _rbMdmNo, _txtMdmNotes });

            _chkDeskPhone.CheckedChanged += (s, e) => {
                _phonePanel.Visible = _chkDeskPhone.Checked;
                RaiseDataChanged();
            };
        }

        public override void LoadData(OnboardingRecord r)
        {
            _loading = true;
            _chkDeskPhone.Checked   = r.DeskPhoneRequired;
            _phonePanel.Visible     = r.DeskPhoneRequired;
            _txtExtension.Text      = r.Extension;
            _txtPhoneModel.Text     = r.PhoneModel;
            foreach (var cb in _chkVoicemail) cb.Checked = r.VoicemailSetupOptions.Contains(cb.Text);
            _txtMobileType.Text     = r.MobileDeviceType;
            _txtMobileNumber.Text   = r.MobileNumber;
            _txtMobileCarrier.Text  = r.MobileCarrier;
            _rbMdmYes.Checked       = r.MdmEnrollment;
            _rbMdmNo.Checked        = !r.MdmEnrollment;
            _txtMdmNotes.Text       = r.MdmNotes;
            _loading = false;
        }

        public override OnboardingRecord SaveData(OnboardingRecord r)
        {
            r.DeskPhoneRequired = _chkDeskPhone.Checked;
            r.Extension         = _txtExtension.Text.Trim();
            r.PhoneModel        = _txtPhoneModel.Text.Trim();
            r.VoicemailSetupOptions.Clear();
            foreach (var cb in _chkVoicemail) if (cb.Checked) r.VoicemailSetupOptions.Add(cb.Text);
            r.MobileDeviceType  = _txtMobileType.Text.Trim();
            r.MobileNumber      = _txtMobileNumber.Text.Trim();
            r.MobileCarrier     = _txtMobileCarrier.Text.Trim();
            r.MdmEnrollment     = _rbMdmYes.Checked;
            r.MdmNotes          = _txtMdmNotes.Text.Trim();
            return r;
        }
    }
}
