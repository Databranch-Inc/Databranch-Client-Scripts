// =============================================================
// ArnotOnboarding — NewEmployeeDialog.cs
// Version    : 1.0.0.0
// Author     : Sam Kirsch
// Company    : Databranch
// Created    : 2026-02-22
// Modified   : 2026-02-22
// Description: Lightweight dialog shown before opening the wizard
//              for a new onboarding. Collects first and last name,
//              then returns OK so the caller can create the draft.
// =============================================================

using System;
using System.Drawing;
using System.Windows.Forms;
using ArnotOnboarding.Theme;

namespace ArnotOnboarding.Views
{
    public class NewEmployeeDialog : Form
    {
        public string FirstName { get; private set; }
        public string LastName  { get; private set; }

        private TextBox _txtFirst;
        private TextBox _txtLast;
        private Button  _btnOk;
        private Button  _btnCancel;

        public NewEmployeeDialog()
        {
            this.Text            = "New Onboarding — Employee Name";
            this.FormBorderStyle = FormBorderStyle.FixedDialog;
            this.MaximizeBox     = false;
            this.MinimizeBox     = false;
            this.StartPosition   = FormStartPosition.CenterParent;
            this.Size            = new Size(420, 240);
            this.BackColor       = AppColors.SurfaceCard;
            this.ForeColor       = AppColors.TextSecondary;

            var lblHeader = new Label
            {
                Text      = "Who is being onboarded?",
                Font      = AppFonts.Heading3,
                ForeColor = AppColors.TextPrimary,
                AutoSize  = true,
                Location  = new Point(24, 20)
            };

            var lblFirst = new Label { Text = "First Name", Font = AppFonts.LabelBold, ForeColor = AppColors.TextSecondary, AutoSize = true, Location = new Point(24, 62) };
            _txtFirst = new TextBox { Location = new Point(24, 82), Size = new Size(172, 26), BackColor = AppColors.SurfaceVoid, ForeColor = AppColors.TextPrimary, BorderStyle = BorderStyle.FixedSingle, Font = AppFonts.Body };

            var lblLast = new Label { Text = "Last Name", Font = AppFonts.LabelBold, ForeColor = AppColors.TextSecondary, AutoSize = true, Location = new Point(212, 62) };
            _txtLast  = new TextBox { Location = new Point(212, 82), Size = new Size(172, 26), BackColor = AppColors.SurfaceVoid, ForeColor = AppColors.TextPrimary, BorderStyle = BorderStyle.FixedSingle, Font = AppFonts.Body };

            _btnOk = new Button { Text = "Start Onboarding", Size = new Size(148, 36), Location = new Point(212, 156), DialogResult = DialogResult.OK };
            ThemeHelper.ApplyButtonStyle(_btnOk, ThemeHelper.ButtonStyle.Primary);
            _btnOk.Click += OnOkClick;

            _btnCancel = new Button { Text = "Cancel", Size = new Size(80, 36), Location = new Point(120, 156), DialogResult = DialogResult.Cancel };
            ThemeHelper.ApplyButtonStyle(_btnCancel, ThemeHelper.ButtonStyle.Ghost);

            this.AcceptButton = _btnOk;
            this.CancelButton = _btnCancel;

            Controls.AddRange(new Control[] { lblHeader, lblFirst, _txtFirst, lblLast, _txtLast, _btnOk, _btnCancel });

            // Wire Enter key on either field to try submit
            _txtFirst.KeyDown += (s, e) => { if (e.KeyCode == Keys.Tab) { _txtLast.Focus(); e.Handled = true; } };
        }

        private void OnOkClick(object sender, EventArgs e)
        {
            if (string.IsNullOrWhiteSpace(_txtFirst.Text) || string.IsNullOrWhiteSpace(_txtLast.Text))
            {
                MessageBox.Show("Please enter both first and last name.", "Required",
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
                this.DialogResult = DialogResult.None; // Keep dialog open
                return;
            }
            FirstName = _txtFirst.Text.Trim();
            LastName  = _txtLast.Text.Trim();
        }
    }
}
