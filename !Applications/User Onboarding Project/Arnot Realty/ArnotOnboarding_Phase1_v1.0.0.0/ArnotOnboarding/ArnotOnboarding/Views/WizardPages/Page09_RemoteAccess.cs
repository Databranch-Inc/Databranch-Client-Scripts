// =============================================================
// ArnotOnboarding — Page09_RemoteAccess.cs  v1.0.0.0
// Description: Remote access — Steps 15-16. VPN, remote desktop options.
// =============================================================
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;
using ArnotOnboarding.Managers;
using ArnotOnboarding.Models;

namespace ArnotOnboarding.Views.WizardPages
{
    public class Page09_RemoteAccess : WizardPageBase
    {
        public override string PageTitle => "Remote Access";

        private RadioButton _rbVpnYes;
        private RadioButton _rbVpnNo;
        private Panel       _vpnDetailPanel;
        private TextBox     _txtVpnUsername;
        private ComboBox    _cboVpnType;
        private readonly List<RadioButton> _rdoVpnTypes = new List<RadioButton>();
        private readonly List<CheckBox>    _chkRemoteDesktop = new List<CheckBox>();

        public Page09_RemoteAccess()
        {
            int y = START_Y;
            Controls.Add(MakeSectionHeader("Step 15 — VPN Access", y)); y += 32;

            Controls.Add(MakeLabel("VPN Required", y));
            _rbVpnYes = MakeRadioButton("Yes", y); y += 28;
            _rbVpnNo  = MakeRadioButton("No",  y); y += ROW_HEIGHT;
            _rbVpnNo.Checked = true;

            // VPN detail panel (shown only when Yes)
            _vpnDetailPanel = new Panel
            {
                Location  = new Point(COL_LABEL_X, y),
                Size      = new Size(COL_LABEL_W + COL_FIELD_W + 40, 160),
                BackColor = Theme.AppColors.SurfaceCard,
                Visible   = false,
                Padding   = new Padding(0, 8, 0, 8)
            };

            int py = 8;
            var lblUser = MakeLabel("VPN Username", py);
            lblUser.Location = new Point(COL_LABEL_X, py + 4);
            _txtVpnUsername = MakeTextBox(py);
            py += ROW_HEIGHT;

            var lblType = MakeLabel("VPN Type", py);
            lblType.Location = new Point(COL_LABEL_X, py + 4);
            var vpnTypes = AppSettingsManager.Instance.Customer.VpnTypes;
            _cboVpnType = new ComboBox
            {
                Location      = new Point(COL_FIELD_X, py),
                Size          = new Size(220, 26),
                DropDownStyle = ComboBoxStyle.DropDownList,
                BackColor     = Theme.AppColors.SurfaceVoid,
                ForeColor     = Theme.AppColors.TextPrimary,
                FlatStyle     = FlatStyle.Flat
            };
            _cboVpnType.Items.AddRange(vpnTypes.ToArray());
            if (_cboVpnType.Items.Count > 0) _cboVpnType.SelectedIndex = 0;
            _cboVpnType.SelectedIndexChanged += (s, e) => RaiseDataChanged();

            _vpnDetailPanel.Controls.AddRange(new Control[] { lblUser, _txtVpnUsername, lblType, _cboVpnType });
            Controls.Add(_vpnDetailPanel);
            y += 170;

            Controls.Add(MakeDivider(y)); y += 16;
            Controls.Add(MakeSectionHeader("Step 16 — Remote Desktop", y)); y += 32;
            Controls.Add(MakeNoteLabel("Select all remote desktop options that apply:", y)); y += 24;

            var rdOptions = AppSettingsManager.Instance.Customer.RemoteDesktopOptions;
            foreach (string opt in rdOptions)
            {
                var cb = MakeCheckBox(opt, y);
                _chkRemoteDesktop.Add(cb);
                Controls.Add(cb);
                y += 30;
            }

            Controls.AddRange(new Control[] { _rbVpnYes, _rbVpnNo });

            _rbVpnYes.CheckedChanged += (s, e) => {
                _vpnDetailPanel.Visible = _rbVpnYes.Checked;
                RaiseDataChanged();
            };
            _rbVpnNo.CheckedChanged += (s, e) => RaiseDataChanged();
        }

        public override void LoadData(OnboardingRecord r)
        {
            _loading = true;
            _rbVpnYes.Checked       = r.VpnRequired;
            _rbVpnNo.Checked        = !r.VpnRequired;
            _vpnDetailPanel.Visible = r.VpnRequired;
            _txtVpnUsername.Text    = r.VpnUsername;
            int vIdx = _cboVpnType.FindStringExact(r.VpnType);
            if (vIdx >= 0) _cboVpnType.SelectedIndex = vIdx;

            foreach (var cb in _chkRemoteDesktop)
                cb.Checked = r.RemoteDesktopOptions.Contains(cb.Text);
            _loading = false;
        }

        public override OnboardingRecord SaveData(OnboardingRecord r)
        {
            r.VpnRequired  = _rbVpnYes.Checked;
            r.VpnUsername  = _txtVpnUsername.Text.Trim();
            r.VpnType      = _cboVpnType.SelectedItem != null ? _cboVpnType.SelectedItem.ToString() : string.Empty;
            r.RemoteDesktopOptions.Clear();
            foreach (var cb in _chkRemoteDesktop)
                if (cb.Checked) r.RemoteDesktopOptions.Add(cb.Text);
            return r;
        }
    }
}
