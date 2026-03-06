// =============================================================
// ArnotOnboarding — Page06_Computer.cs
// Version    : 1.6.0.0
// Changes:
//   • Q12 computer name syncs bidirectionally with Page02 Primary Computer Name
//   • 13b "New location" added — greyed when Step 13 = No
//   • 12b greyed when 12a = No
//   • 13a greyed when Step 13 = No
// =============================================================
using System;
using System.Drawing;
using System.Windows.Forms;
using ArnotOnboarding.Models;
using ArnotOnboarding.Theme;

namespace ArnotOnboarding.Views.WizardPages
{
    public class Page06_Computer : WizardPageBase
    {
        public override string PageTitle => "Computer Setup (Steps 10-14)";

        // Step 10
        private Panel _grp10; private RadioButton _rb10Existing, _rb10New;
        // Step 11
        private Panel _grp11; private RadioButton _rb11Yes, _rb11No;
        // Step 12
        private TextBox _txt12ComputerName;
        private Label   _lbl12;
        private Panel   _grp12Rename; private RadioButton _rb12RenameYes, _rb12RenameNo;
        private TextBox _txt12NewName;
        private Label   _lbl12b;
        // Step 13
        private Panel _grp13; private RadioButton _rb13Yes, _rb13No;
        private TextBox _txt13Location;
        private Label   _lbl13a;
        private TextBox _txt13NewLocation;
        private Label   _lbl13b;
        // Step 14
        private Panel _grp14; private RadioButton _rb14Yes, _rb14No;
        private Panel _grp14Compat; private RadioButton _rb14CompatYes, _rb14CompatNo;
        private Panel _grp14DockType; private RadioButton _rb14USBC, _rb14DockOther;

        // Raised when computer name changes so WizardView can push to Page02
        public event EventHandler<string> ComputerNameChanged;

        public Page06_Computer()
        {
            int y = START_Y;

            // ── Step 10 ───────────────────────────────────────────────
            Controls.Add(MakeSectionHeader("Step 10 — Is the User's Computer Existing or New?", y)); y += 32;
            _grp10 = MakeRPanel(y, "Existing", "New", out _rb10Existing, out _rb10New);
            Controls.Add(_grp10); y += ROW_HEIGHT;
            Controls.Add(MakeNoteLabel("If New, refer to New Computer Request Form for Computer, Access & Equipment information.", y - 14));

            // ── Step 11 ───────────────────────────────────────────────
            Controls.Add(MakeDivider(y)); y += 12;
            Controls.Add(MakeLabel("Step 11 — Reset existing\ncomputer to factory settings?", y));
            _grp11 = MakeRPanel(y, "Yes", "No", out _rb11Yes, out _rb11No);
            Controls.Add(_grp11); y += ROW_HEIGHT;

            // ── Step 12 ───────────────────────────────────────────────
            Controls.Add(MakeDivider(y)); y += 12;
            Controls.Add(MakeSectionHeader("Step 12 — Existing Computer Name", y)); y += 32;

            _lbl12 = MakeLabel("12) Computer Name", y);
            Controls.Add(_lbl12);
            _txt12ComputerName = MakeTextBox(y); Controls.Add(_txt12ComputerName);
            Controls.Add(MakeNoteLabel("Synced with Primary Computer Name on Page 2", y + 28)); 
            y += ROW_HEIGHT + 14;

            // Raise event so WizardView can push name back to Page02
            _txt12ComputerName.TextChanged += (s, e) =>
            {
                RaiseDataChanged();
                if (!_loading) ComputerNameChanged?.Invoke(this, _txt12ComputerName.Text);
            };

            Controls.Add(MakeLabel("12a) Rename computer?", y));
            _grp12Rename = MakeRPanel(y, "Yes", "No", out _rb12RenameYes, out _rb12RenameNo);
            Controls.Add(_grp12Rename); y += ROW_HEIGHT;

            _lbl12b = MakeLabel("12b) New Name", y);
            Controls.Add(_lbl12b);
            _txt12NewName = MakeTextBox(y); Controls.Add(_txt12NewName);
            Controls.Add(MakeNoteLabel("Format: Company & Department Prefix (ex. AXXX-COR)", y + 28));
            y += ROW_HEIGHT + 14;

            _rb12RenameYes.CheckedChanged += (s, e) => UpdateGreyStates();
            _rb12RenameNo.CheckedChanged  += (s, e) => UpdateGreyStates();

            // ── Step 13 ───────────────────────────────────────────────
            Controls.Add(MakeDivider(y)); y += 12;
            Controls.Add(MakeLabel("Step 13 — Existing computer\nneed to be relocated?", y));
            _grp13 = MakeRPanel(y, "Yes", "No", out _rb13Yes, out _rb13No);
            Controls.Add(_grp13); y += ROW_HEIGHT;

            _lbl13a = MakeLabel("13a) If yes, current\nlocation:", y);
            Controls.Add(_lbl13a);
            _txt13Location = MakeTextBox(y); Controls.Add(_txt13Location); y += ROW_HEIGHT;

            _lbl13b = MakeLabel("13b) New location:", y);
            Controls.Add(_lbl13b);
            _txt13NewLocation = MakeTextBox(y); Controls.Add(_txt13NewLocation); y += ROW_HEIGHT;

            _rb13Yes.CheckedChanged += (s, e) => UpdateGreyStates();
            _rb13No.CheckedChanged  += (s, e) => UpdateGreyStates();

            // ── Step 14 ───────────────────────────────────────────────
            Controls.Add(MakeDivider(y)); y += 12;
            Controls.Add(MakeLabel("Step 14 — Docking station\nrequired?", y));
            _grp14 = MakeRPanel(y, "Yes", "No", out _rb14Yes, out _rb14No);
            Controls.Add(_grp14); y += ROW_HEIGHT;

            Controls.Add(MakeLabel("14a) Compatible dock in\nuser's location?", y));
            _grp14Compat = MakeRPanel(y, "Yes", "No", out _rb14CompatYes, out _rb14CompatNo);
            Controls.Add(_grp14Compat); y += ROW_HEIGHT;

            Controls.Add(MakeLabel("14b) If No, dock type:", y));
            _grp14DockType = MakeRPanel(y, "USB-C", "Other", out _rb14USBC, out _rb14DockOther);
            Controls.Add(_grp14DockType);

            UpdateGreyStates();
        }

        // ── Public sync — called by WizardView when Page02 name changes ──

        public void SyncComputerName(string name)
        {
            if (_loading) return;
            _loading = true;
            _txt12ComputerName.Text = name;
            _loading = false;
        }

        // ── Grey-out logic ────────────────────────────────────────────

        private void UpdateGreyStates()
        {
            // 12b: editable only when 12a = Yes
            bool rename = _rb12RenameYes.Checked;
            _txt12NewName.ReadOnly  = !rename;
            _txt12NewName.BackColor = rename ? AppColors.SurfaceVoid : AppColors.SurfaceBase;
            _txt12NewName.ForeColor = rename ? AppColors.TextSecondary : AppColors.TextDim;
            _lbl12b.ForeColor       = rename ? AppColors.TextSecondary : AppColors.TextDim;

            // 13a + 13b: editable only when Step 13 = Yes
            bool relocate = _rb13Yes.Checked;
            SetFieldGrey(_txt13Location,    _lbl13a, relocate);
            SetFieldGrey(_txt13NewLocation, _lbl13b, relocate);
        }

        private void SetFieldGrey(TextBox tb, Label lbl, bool enabled)
        {
            tb.ReadOnly  = !enabled;
            tb.BackColor = enabled ? AppColors.SurfaceVoid : AppColors.SurfaceBase;
            tb.ForeColor = enabled ? AppColors.TextSecondary : AppColors.TextDim;
            lbl.ForeColor = enabled ? AppColors.TextSecondary : AppColors.TextDim;
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

        public override void LoadData(OnboardingRecord r)
        {
            _loading = true;
            SetR(_rb10Existing, _rb10New, r.ComputerExisting);
            SetR(_rb11Yes, _rb11No, r.ResetToFactory);
            _txt12ComputerName.Text   = r.ExistingComputerName;
            SetR(_rb12RenameYes, _rb12RenameNo, r.RenameComputer);
            _txt12NewName.Text        = r.ComputerNewName;
            SetR(_rb13Yes, _rb13No, r.RelocateComputer);
            _txt13Location.Text       = r.ComputerCurrentLocation;
            _txt13NewLocation.Text    = r.ComputerNewLocation;
            SetR(_rb14Yes, _rb14No, r.DockingStationRequired);
            SetR(_rb14CompatYes, _rb14CompatNo, r.DockingCompatible);
            SetR(_rb14USBC, _rb14DockOther, r.DockTypeUSBC);
            _loading = false;
            UpdateGreyStates();
        }

        public override OnboardingRecord SaveData(OnboardingRecord r)
        {
            r.ComputerExisting        = _rb10Existing.Checked;
            r.ResetToFactory          = _rb11Yes.Checked;
            r.ExistingComputerName    = _txt12ComputerName.Text.Trim();
            r.PrimaryComputerName     = r.ExistingComputerName; // keep in sync
            r.RenameComputer          = _rb12RenameYes.Checked;
            r.ComputerNewName         = _txt12NewName.Text.Trim();
            r.RelocateComputer        = _rb13Yes.Checked;
            r.ComputerCurrentLocation = _txt13Location.Text.Trim();
            r.ComputerNewLocation     = _txt13NewLocation.Text.Trim();
            r.DockingStationRequired  = _rb14Yes.Checked;
            r.DockingCompatible       = _rb14CompatYes.Checked;
            r.DockTypeUSBC            = _rb14USBC.Checked;
            return r;
        }

        private void SetR(RadioButton r1, RadioButton r2, bool v) { r1.Checked = v; r2.Checked = !v; }
    }
}
