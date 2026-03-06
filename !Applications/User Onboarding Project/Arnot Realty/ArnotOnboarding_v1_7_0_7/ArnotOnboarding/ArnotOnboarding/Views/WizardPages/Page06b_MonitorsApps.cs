// =============================================================
// ArnotOnboarding — Page06b_MonitorsApps.cs
// Version    : 1.5.8.0
// Description: Steps 15–16 split from Page06 onto their own page.
//              Monitor connectors are radio buttons (single-select per monitor).
// =============================================================
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;
using ArnotOnboarding.Models;
using ArnotOnboarding.Theme;

namespace ArnotOnboarding.Views.WizardPages
{
    public class Page06b_MonitorsApps : WizardPageBase
    {
        public override string PageTitle => "Monitors & Applications (Steps 15-16)";

        // Step 15
        private Panel _grp15; private RadioButton _rb15Yes, _rb15No;
        private Panel _grp15Count; private RadioButton _rb151Mon, _rb152Mon;
        private TextBox _txt15Sizes;
        private Panel _grpMon1Type; private RadioButton _rb15Mon1New, _rb15Mon1Existing;
        private Panel _grpMon2Type; private RadioButton _rb15Mon2New, _rb15Mon2Existing;
        // Connector radio buttons (single-select per monitor)
        private Panel _grpConn1; private RadioButton _rb15VGA1, _rb15DVI1, _rb15HDMI1, _rb15DP1;
        private Panel _grpConn2; private RadioButton _rb15VGA2, _rb15DVI2, _rb15HDMI2, _rb15DP2;
        // Step 16
        private readonly List<CheckBox> _appChecks = new List<CheckBox>();
        private TextBox _txtApp1, _txtApp2, _txtApp3;

        private static readonly string[] APPS = {
            "Adobe Acrobat Pro",           "Google Earth",               "SNAPmobile (mobile)",
            "Adobe Acrobat Standard",      "iViewer (mobile)",           "Stamps.com",
            "Adobe Creative Suite",        "LastPass browser extension", "Vast2",
            "Adobe Acrobat Reader",        "Microsoft Office Suite",     "Zoom",
            "Appfolio (desktop & mobile)", "Revit LT",                   null,
            "AutoCAD LT",                  "Remote access to Doors PC",  null,
            "Duo Security app (mobile)",   "SketchUp Pro",               null,
        };

        public Page06b_MonitorsApps()
        {
            int y = START_Y;

            // ── Step 15 — Monitors ────────────────────────────────────
            Controls.Add(MakeSectionHeader("Step 15 — Additional Monitors", y)); y += 32;
            Controls.Add(MakeLabel("15) Additional monitors\nrequired?", y));
            _grp15 = MakeRPanel(y, "Yes", "No", out _rb15Yes, out _rb15No);
            Controls.Add(_grp15); y += ROW_HEIGHT;

            Controls.Add(MakeLabel("15a) How many total?\n(not incl. laptop)", y));
            _grp15Count = MakeRPanel(y, "1", "2", out _rb151Mon, out _rb152Mon);
            Controls.Add(_grp15Count); y += ROW_HEIGHT;

            Controls.Add(MakeLabel("15b) What sizes needed?", y));
            _txt15Sizes = MakeTextBox(y, 220); Controls.Add(_txt15Sizes); y += ROW_HEIGHT;

            // Monitor 1 & 2 side-by-side columns
            int cx1 = COL_FIELD_X, cx2 = COL_FIELD_X + 200;

            Controls.Add(new Label { Text = "Monitor 1", Location = new Point(cx1, y), Size = new Size(190, 18), Font = AppFonts.LabelBold, ForeColor = AppColors.TextMuted, BackColor = Color.Transparent });
            Controls.Add(new Label { Text = "Monitor 2", Location = new Point(cx2, y), Size = new Size(190, 18), Font = AppFonts.LabelBold, ForeColor = AppColors.TextMuted, BackColor = Color.Transparent });
            y += 22;

            // New / Existing radio per monitor
            _grpMon1Type = MakeMonitorTypePanel(cx1, y, out _rb15Mon1New, out _rb15Mon1Existing);
            Controls.Add(_grpMon1Type);
            _grpMon2Type = MakeMonitorTypePanel(cx2, y, out _rb15Mon2New, out _rb15Mon2Existing);
            Controls.Add(_grpMon2Type);
            y += 28;

            // Connector radio buttons — vertical stack, single-select per monitor
            _grpConn1 = MakeConnectorPanel(cx1, y, out _rb15VGA1, out _rb15DVI1, out _rb15HDMI1, out _rb15DP1);
            Controls.Add(_grpConn1);
            _grpConn2 = MakeConnectorPanel(cx2, y, out _rb15VGA2, out _rb15DVI2, out _rb15HDMI2, out _rb15DP2);
            Controls.Add(_grpConn2);
            y += 4 * 22 + 8; // 4 rows × 22px + gap

            // ── Step 16 — Applications ────────────────────────────────
            Controls.Add(MakeDivider(y)); y += 12;
            Controls.Add(MakeSectionHeader("Step 16 — Applications to Set Up", y)); y += 32;

            int ay = y, col = 0;
            int[] colX = { COL_FIELD_X, COL_FIELD_X + 200, COL_FIELD_X + 400 };
            foreach (string app in APPS)
            {
                if (app != null)
                {
                    var cb = new CheckBox
                    {
                        Text      = app,
                        Location  = new Point(colX[col % 3], ay + (col / 3) * 26),
                        Size      = new Size(195, 24),
                        BackColor = Color.Transparent,
                        ForeColor = AppColors.TextSecondary,
                        Font      = AppFonts.BodySmall
                    };
                    cb.CheckedChanged += (s, e) => RaiseDataChanged();
                    Controls.Add(cb);
                    _appChecks.Add(cb);
                }
                col++;
            }
            y += ((APPS.Length / 3) + 1) * 26 + 8;

            Controls.Add(MakeLabel("16) Other apps:", y));
            _txtApp1 = MakeTextBox(y, 180); Controls.Add(_txtApp1); y += ROW_HEIGHT;
            _txtApp2 = MakeTextBox(y, 180); Controls.Add(_txtApp2); y += ROW_HEIGHT;
            _txtApp3 = MakeTextBox(y, 180); Controls.Add(_txtApp3);
        }

        // ── Layout helpers ────────────────────────────────────────────

        private Panel MakeConnectorPanel(int x, int y,
            out RadioButton rbVGA, out RadioButton rbDVI,
            out RadioButton rbHDMI, out RadioButton rbDP)
        {
            var p = new Panel
            {
                Location  = new Point(x, y),
                Size      = new Size(180, 4 * 22),
                BackColor = Color.Transparent
            };
            rbVGA  = MakeConnRB("VGA",  0,  p);
            rbDVI  = MakeConnRB("DVI",  22, p);
            rbHDMI = MakeConnRB("HDMI", 44, p);
            rbDP   = MakeConnRB("DP",   66, p);
            rbVGA.Checked = true; // default
            return p;
        }

        private RadioButton MakeConnRB(string text, int top, Panel parent)
        {
            var rb = new RadioButton
            {
                Text      = text,
                Location  = new Point(0, top),
                Size      = new Size(100, 20),
                BackColor = Color.Transparent,
                ForeColor = AppColors.TextSecondary,
                Font      = AppFonts.BodySmall
            };
            rb.CheckedChanged += (s, e) => RaiseDataChanged();
            parent.Controls.Add(rb);
            return rb;
        }

        private Panel MakeMonitorTypePanel(int x, int y,
            out RadioButton rbNew, out RadioButton rbExisting)
        {
            var p = new Panel { Location = new Point(x, y), Size = new Size(180, 24), BackColor = Color.Transparent };
            rbNew = new RadioButton { Text = "New", Location = new Point(0, 1), Size = new Size(68, 22), BackColor = Color.Transparent, ForeColor = AppColors.TextSecondary, Font = AppFonts.BodySmall };
            rbExisting = new RadioButton { Text = "Existing", Location = new Point(72, 1), Size = new Size(80, 22), BackColor = Color.Transparent, ForeColor = AppColors.TextSecondary, Font = AppFonts.BodySmall };
            rbNew.Checked = true;
            rbNew.CheckedChanged      += (s, e) => RaiseDataChanged();
            rbExisting.CheckedChanged += (s, e) => RaiseDataChanged();
            p.Controls.Add(rbNew); p.Controls.Add(rbExisting);
            return p;
        }

        private Panel MakeRPanel(int y, string l1, string l2, out RadioButton r1, out RadioButton r2)
        {
            var p = new Panel { Location = new Point(COL_FIELD_X, y), Size = new Size(COL_FIELD_W, 26), BackColor = Color.Transparent };
            r1 = new RadioButton { Text = l1, Location = new Point(0, 2),   Size = new Size(90, 22), BackColor = Color.Transparent, ForeColor = AppColors.TextSecondary, Font = AppFonts.Body };
            r2 = new RadioButton { Text = l2, Location = new Point(100, 2), Size = new Size(90, 22), BackColor = Color.Transparent, ForeColor = AppColors.TextSecondary, Font = AppFonts.Body };
            r2.Checked = true;
            r1.CheckedChanged += (s, e) => RaiseDataChanged();
            r2.CheckedChanged += (s, e) => RaiseDataChanged();
            p.Controls.Add(r1); p.Controls.Add(r2);
            return p;
        }

        // ── String helper for connector save/load ─────────────────────

        private string GetConnector(RadioButton vga, RadioButton dvi, RadioButton hdmi, RadioButton dp)
        {
            if (vga.Checked)  return "VGA";
            if (dvi.Checked)  return "DVI";
            if (hdmi.Checked) return "HDMI";
            if (dp.Checked)   return "DP";
            return "VGA";
        }

        private void SetConnector(string val, RadioButton vga, RadioButton dvi, RadioButton hdmi, RadioButton dp)
        {
            vga.Checked  = (val == "VGA");
            dvi.Checked  = (val == "DVI");
            hdmi.Checked = (val == "HDMI");
            dp.Checked   = (val == "DP");
            if (!vga.Checked && !dvi.Checked && !hdmi.Checked && !dp.Checked)
                vga.Checked = true;
        }

        // ── IWizardPage ───────────────────────────────────────────────

        public override void LoadData(OnboardingRecord r)
        {
            _loading = true;
            SetR(_rb15Yes, _rb15No, r.AdditionalMonitors);
            SetR(_rb151Mon, _rb152Mon, r.MonitorCount == 1);
            _txt15Sizes.Text = r.MonitorSizes;
            SetR(_rb15Mon1New, _rb15Mon1Existing, r.Monitor1New);
            SetR(_rb15Mon2New, _rb15Mon2Existing, r.Monitor2New);
            SetConnector(r.Monitor1Connector, _rb15VGA1, _rb15DVI1, _rb15HDMI1, _rb15DP1);
            SetConnector(r.Monitor2Connector, _rb15VGA2, _rb15DVI2, _rb15HDMI2, _rb15DP2);
            foreach (var cb in _appChecks) cb.Checked = r.Applications.Contains(cb.Text);
            _txtApp1.Text = r.ApplicationOther1;
            _txtApp2.Text = r.ApplicationOther2;
            _txtApp3.Text = r.ApplicationOther3;
            _loading = false;
        }

        public override OnboardingRecord SaveData(OnboardingRecord r)
        {
            r.AdditionalMonitors = _rb15Yes.Checked;
            r.MonitorCount       = _rb151Mon.Checked ? 1 : 2;
            r.MonitorSizes       = _txt15Sizes.Text.Trim();
            r.Monitor1New        = _rb15Mon1New.Checked;
            r.Monitor1Existing   = _rb15Mon1Existing.Checked;
            r.Monitor2New        = _rb15Mon2New.Checked;
            r.Monitor2Existing   = _rb15Mon2Existing.Checked;
            r.Monitor1Connector  = GetConnector(_rb15VGA1, _rb15DVI1, _rb15HDMI1, _rb15DP1);
            r.Monitor2Connector  = GetConnector(_rb15VGA2, _rb15DVI2, _rb15HDMI2, _rb15DP2);
            r.Applications.Clear();
            foreach (var cb in _appChecks) if (cb.Checked) r.Applications.Add(cb.Text);
            r.ApplicationOther1 = _txtApp1.Text.Trim();
            r.ApplicationOther2 = _txtApp2.Text.Trim();
            r.ApplicationOther3 = _txtApp3.Text.Trim();
            return r;
        }

        private void SetR(RadioButton r1, RadioButton r2, bool v) { r1.Checked = v; r2.Checked = !v; }
    }
}
