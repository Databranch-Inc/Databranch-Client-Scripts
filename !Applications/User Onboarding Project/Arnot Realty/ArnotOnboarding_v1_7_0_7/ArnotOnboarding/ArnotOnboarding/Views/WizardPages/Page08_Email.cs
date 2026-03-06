// =============================================================
// ArnotOnboarding — Page08_Email.cs
// Version    : 1.6.0.0
// Changes:
//   • 21a greyed/locked when 21 = No
//   • 22a greyed/locked when 22 = No
//   • 25a greyed/locked when 25 = No
// =============================================================
using System.Drawing;
using System.Windows.Forms;
using ArnotOnboarding.Models;
using ArnotOnboarding.Theme;

namespace ArnotOnboarding.Views.WizardPages
{
    public class Page08_Email : WizardPageBase
    {
        public override string PageTitle => "Email (Steps 21-25)";

        private Panel _grp21; private RadioButton _rb21Yes, _rb21No;
        private TextBox _txt21Mailboxes;
        private Label   _lbl21a;
        private Panel _grp22; private RadioButton _rb22Yes, _rb22No;
        private TextBox _txt22DistribLists;
        private Label   _lbl22a;
        private Panel _grp25; private RadioButton _rb25Yes, _rb25No;
        private TextBox _txt25Aliases;
        private Label   _lbl25a;

        public Page08_Email()
        {
            int y = START_Y;
            Controls.Add(MakeSectionHeader("Email (Steps 21-25)", y)); y += 32;

            // ── Step 21 ───────────────────────────────────────────────
            Controls.Add(MakeLabel("21) Shared mailboxes?", y));
            _grp21 = MakeRPanel(y, "Yes", "No", out _rb21Yes, out _rb21No);
            Controls.Add(_grp21); y += ROW_HEIGHT;

            _lbl21a = MakeLabel("21a) Mailbox addresses:", y);
            Controls.Add(_lbl21a);
            _txt21Mailboxes = MakeMultiLineTextBox(y, 60);
            Controls.Add(MakeNoteLabel("One email address per line", y + 62));
            Controls.Add(_txt21Mailboxes); y += 80;

            _rb21Yes.CheckedChanged += (s, e) => UpdateGreyStates();
            _rb21No.CheckedChanged  += (s, e) => UpdateGreyStates();

            // ── Step 22 ───────────────────────────────────────────────
            Controls.Add(MakeDivider(y)); y += 12;
            Controls.Add(MakeLabel("22) Distribution lists?", y));
            _grp22 = MakeRPanel(y, "Yes", "No", out _rb22Yes, out _rb22No);
            Controls.Add(_grp22); y += ROW_HEIGHT;

            _lbl22a = MakeLabel("22a) Distribution lists:", y);
            Controls.Add(_lbl22a);
            _txt22DistribLists = MakeMultiLineTextBox(y, 60);
            Controls.Add(MakeNoteLabel("One list per line. Databranch engineer will add user.", y + 62));
            Controls.Add(_txt22DistribLists); y += 80;

            _rb22Yes.CheckedChanged += (s, e) => UpdateGreyStates();
            _rb22No.CheckedChanged  += (s, e) => UpdateGreyStates();

            // ── Steps 23 & 24 — Databranch engineer tasks ─────────────
            Controls.Add(MakeDivider(y)); y += 12;
            var note23 = new Label
            {
                Text      = "Step 23: Databranch engineer — Add employee and resource calendars " +
                            "(Small Conference, Board Room)\n" +
                            "Step 24: Databranch engineer — Setup email signature",
                Location  = new Point(COL_FIELD_X, y),
                Size      = new Size(COL_FIELD_W_WIDE, 44),
                Font      = AppFonts.BodySmall,
                ForeColor = AppColors.BrandRedPale,
                BackColor = Color.Transparent
            };
            Controls.Add(note23); y += 54;

            // ── Step 25 ───────────────────────────────────────────────
            Controls.Add(MakeDivider(y)); y += 12;
            Controls.Add(MakeLabel("25) Additional email\naliases?", y));
            _grp25 = MakeRPanel(y, "Yes", "No", out _rb25Yes, out _rb25No);
            Controls.Add(_grp25); y += ROW_HEIGHT;

            _lbl25a = MakeLabel("25a) Alias addresses:", y);
            Controls.Add(_lbl25a);
            _txt25Aliases = MakeMultiLineTextBox(y, 60);
            Controls.Add(MakeNoteLabel("One email address per line", y + 62));
            Controls.Add(_txt25Aliases);

            _rb25Yes.CheckedChanged += (s, e) => UpdateGreyStates();
            _rb25No.CheckedChanged  += (s, e) => UpdateGreyStates();

            UpdateGreyStates();
        }

        private void UpdateGreyStates()
        {
            SetMultiGrey(_txt21Mailboxes, _lbl21a, _rb21Yes.Checked);
            SetMultiGrey(_txt22DistribLists, _lbl22a, _rb22Yes.Checked);
            SetMultiGrey(_txt25Aliases, _lbl25a, _rb25Yes.Checked);
        }

        private void SetMultiGrey(TextBox tb, Label lbl, bool enabled)
        {
            tb.ReadOnly  = !enabled;
            tb.BackColor = enabled ? AppColors.SurfaceVoid : AppColors.SurfaceBase;
            tb.ForeColor = enabled ? AppColors.TextSecondary : AppColors.TextDim;
            lbl.ForeColor = enabled ? AppColors.TextSecondary : AppColors.TextDim;
        }

        private Panel MakeRPanel(int y, string l1, string l2, out RadioButton r1, out RadioButton r2)
        {
            var p = new Panel { Location = new Point(COL_FIELD_X, y), Size = new Size(200, 26), BackColor = System.Drawing.Color.Transparent };
            r1 = new RadioButton { Text = l1, Location = new Point(0, 2),  Size = new Size(70, 22), BackColor = System.Drawing.Color.Transparent, ForeColor = AppColors.TextSecondary, Font = AppFonts.Body };
            r2 = new RadioButton { Text = l2, Location = new Point(80, 2), Size = new Size(70, 22), BackColor = System.Drawing.Color.Transparent, ForeColor = AppColors.TextSecondary, Font = AppFonts.Body };
            r2.Checked = true;
            r1.CheckedChanged += (s, e) => RaiseDataChanged();
            r2.CheckedChanged += (s, e) => RaiseDataChanged();
            p.Controls.Add(r1); p.Controls.Add(r2);
            return p;
        }

        public override void LoadData(OnboardingRecord r)
        {
            _loading = true;
            SetR(_rb21Yes, _rb21No, r.SharedMailboxes21);
            _txt21Mailboxes.Text    = r.SharedMailboxList;
            SetR(_rb22Yes, _rb22No, r.DistributionLists22);
            _txt22DistribLists.Text = r.DistributionListText;
            SetR(_rb25Yes, _rb25No, r.EmailAliases25);
            _txt25Aliases.Text      = r.EmailAliasesList;
            _loading = false;
            UpdateGreyStates();
        }

        public override OnboardingRecord SaveData(OnboardingRecord r)
        {
            r.SharedMailboxes21    = _rb21Yes.Checked;
            r.SharedMailboxList    = _txt21Mailboxes.Text.Trim();
            r.DistributionLists22  = _rb22Yes.Checked;
            r.DistributionListText = _txt22DistribLists.Text.Trim();
            r.EmailAliases25       = _rb25Yes.Checked;
            r.EmailAliasesList     = _txt25Aliases.Text.Trim();
            return r;
        }

        private void SetR(RadioButton r1, RadioButton r2, bool v) { r1.Checked = v; r2.Checked = !v; }
    }
}
