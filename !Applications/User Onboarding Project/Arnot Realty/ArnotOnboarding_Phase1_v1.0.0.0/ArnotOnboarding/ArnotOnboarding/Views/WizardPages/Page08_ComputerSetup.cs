// =============================================================
// ArnotOnboarding — Page08_ComputerSetup.cs  v1.0.0.0
// Description: Computer setup — Steps 10-14.
//              New vs existing, printer, monitor count/type.
// =============================================================
using System;
using System.Windows.Forms;
using ArnotOnboarding.Managers;
using ArnotOnboarding.Models;
using ArnotOnboarding.Theme;

namespace ArnotOnboarding.Views.WizardPages
{
    public class Page08_ComputerSetup : WizardPageBase
    {
        public override string PageTitle => "Computer Setup";

        private RadioButton _rbNewComputer;
        private RadioButton _rbExistingComputer;
        private Label       _lblExistingName;
        private TextBox     _txtExistingName;
        private TextBox     _txtPrinters;
        private RadioButton _rb1Monitor;
        private RadioButton _rb2Monitors;
        private Label       _lblMon1Type;
        private ComboBox    _cboMon1Type;
        private Label       _lblMon2Type;
        private ComboBox    _cboMon2Type;

        public Page08_ComputerSetup()
        {
            int y = START_Y;
            Controls.Add(MakeSectionHeader("Step 10 — Computer", y)); y += 32;

            Controls.Add(MakeLabel("Computer", y));
            _rbNewComputer      = MakeRadioButton("New computer",      y); y += 28;
            _rbExistingComputer = MakeRadioButton("Existing computer", y); y += ROW_HEIGHT;
            _rbNewComputer.Checked = true;

            _lblExistingName = MakeLabel("Computer Name", y);
            _txtExistingName = MakeTextBox(y);
            Controls.Add(MakeNoteLabel("Enter the existing computer name or asset tag", y + 28));
            y += ROW_HEIGHT + 14;

            Controls.Add(MakeDivider(y)); y += 16;
            Controls.Add(MakeSectionHeader("Step 13 — Printers", y)); y += 32;

            Controls.Add(MakeLabel("Printers / Queue Names", y));
            _txtPrinters = MakeMultiLineTextBox(y, 56);
            Controls.Add(MakeNoteLabel("One printer per line", y + 58));
            y += 80;

            Controls.Add(MakeDivider(y)); y += 16;
            Controls.Add(MakeSectionHeader("Step 14 — Monitors", y)); y += 32;

            Controls.Add(MakeLabel("Monitor Count", y));
            _rb1Monitor  = MakeRadioButton("1 monitor", y); y += 28;
            _rb2Monitors = MakeRadioButton("2 monitors", y); y += ROW_HEIGHT;
            _rb1Monitor.Checked = true;

            var monTypes = AppSettingsManager.Instance.Customer.MonitorTypes;

            _lblMon1Type = MakeLabel("Monitor 1 Type", y);
            _cboMon1Type = new ComboBox { Location = new System.Drawing.Point(COL_FIELD_X, y), Size = new System.Drawing.Size(260, 26), DropDownStyle = ComboBoxStyle.DropDownList, BackColor = AppColors.SurfaceVoid, ForeColor = AppColors.TextPrimary, FlatStyle = FlatStyle.Flat };
            _cboMon1Type.Items.AddRange(monTypes.ToArray());
            if (_cboMon1Type.Items.Count > 0) _cboMon1Type.SelectedIndex = 0;
            _cboMon1Type.SelectedIndexChanged += (s, e) => RaiseDataChanged();
            y += ROW_HEIGHT;

            _lblMon2Type = MakeLabel("Monitor 2 Type", y);
            _cboMon2Type = new ComboBox { Location = new System.Drawing.Point(COL_FIELD_X, y), Size = new System.Drawing.Size(260, 26), DropDownStyle = ComboBoxStyle.DropDownList, BackColor = AppColors.SurfaceVoid, ForeColor = AppColors.TextPrimary, FlatStyle = FlatStyle.Flat };
            _cboMon2Type.Items.AddRange(monTypes.ToArray());
            if (_cboMon2Type.Items.Count > 0) _cboMon2Type.SelectedIndex = 0;
            _cboMon2Type.SelectedIndexChanged += (s, e) => RaiseDataChanged();

            Controls.AddRange(new Control[]
            {
                _rbNewComputer, _rbExistingComputer, _lblExistingName, _txtExistingName,
                _txtPrinters, _rb1Monitor, _rb2Monitors,
                _lblMon1Type, _cboMon1Type, _lblMon2Type, _cboMon2Type
            });

            _rbExistingComputer.CheckedChanged += (s, e) => {
                bool existing = _rbExistingComputer.Checked;
                _lblExistingName.Visible = existing;
                _txtExistingName.Visible = existing;
                RaiseDataChanged();
            };
            _rb2Monitors.CheckedChanged += (s, e) => {
                _lblMon2Type.Visible = _rb2Monitors.Checked;
                _cboMon2Type.Visible = _rb2Monitors.Checked;
                RaiseDataChanged();
            };

            _lblExistingName.Visible = false;
            _txtExistingName.Visible = false;
            _lblMon2Type.Visible     = false;
            _cboMon2Type.Visible     = false;
        }

        public override void LoadData(OnboardingRecord r)
        {
            _loading = true;
            _rbNewComputer.Checked      = r.NewComputer;
            _rbExistingComputer.Checked = !r.NewComputer;
            _txtExistingName.Text       = r.ExistingComputerName;
            _lblExistingName.Visible    = !r.NewComputer;
            _txtExistingName.Visible    = !r.NewComputer;
            _txtPrinters.Text           = r.Printers;
            _rb1Monitor.Checked         = r.MonitorCount == 1;
            _rb2Monitors.Checked        = r.MonitorCount == 2;

            SetComboValue(_cboMon1Type, r.Monitor1Type);
            SetComboValue(_cboMon2Type, r.Monitor2Type);

            _lblMon2Type.Visible = r.MonitorCount == 2;
            _cboMon2Type.Visible = r.MonitorCount == 2;
            _loading = false;
        }

        public override OnboardingRecord SaveData(OnboardingRecord r)
        {
            r.NewComputer         = _rbNewComputer.Checked;
            r.ExistingComputerName = _txtExistingName.Text.Trim();
            r.Printers            = _txtPrinters.Text.Trim();
            r.MonitorCount        = _rb2Monitors.Checked ? 2 : 1;
            r.Monitor1Type        = _cboMon1Type.SelectedItem != null ? _cboMon1Type.SelectedItem.ToString() : string.Empty;
            r.Monitor2Type        = _cboMon2Type.SelectedItem != null ? _cboMon2Type.SelectedItem.ToString() : string.Empty;
            return r;
        }

        private void SetComboValue(ComboBox cbo, string value)
        {
            if (string.IsNullOrEmpty(value)) return;
            int idx = cbo.FindStringExact(value);
            if (idx >= 0) cbo.SelectedIndex = idx;
        }
    }
}
