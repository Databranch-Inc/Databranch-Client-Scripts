// =============================================================
// ArnotOnboarding — Page07_PrintScanAccess.cs
// Version    : 1.5.8.0
// Fixes:
//   • 17a/18a checkbox spacing corrected — wider boxes, proper offsets
//   • Step 19 labels widened — "R (All Office)" / "Q (EX Office)" no longer clipped
//   • Step 19 R checkbox: clicking checks all R:\\ boxes in Step 20
//     (boxes remain independently uncheckable; re-clicking R re-checks all)
// =============================================================
using System;
using System.Drawing;
using System.Windows.Forms;
using ArnotOnboarding.Models;
using ArnotOnboarding.Theme;

namespace ArnotOnboarding.Views.WizardPages
{
    public class Page07_PrintScanAccess : WizardPageBase
    {
        public override string PageTitle => "Print, Scan & Access (Steps 17-20)";

        // Step 17
        private Panel _grp17; private RadioButton _rb17Yes, _rb17No;
        private CheckBox _chk17Main, _chk17Stillwater, _chk17Ironworks, _chk17Other;
        // Step 18
        private Panel _grp18; private RadioButton _rb18Yes, _rb18No;
        private CheckBox _chk18Main, _chk18Stillwater, _chk18Ironworks, _chk18Other;
        // Step 19
        private CheckBox _chk19R, _chk19Q, _chk19K, _chk19S;
        // Step 20
        private static readonly string[] FOLDERS = {
            "Development","Marketing","Leasing","Services","Operations",
            "Information Systems","Human Resources","Accounting","Finance","Shareholders"
        };
        private CheckBox[] _chk20R, _chk20Q;

        public Page07_PrintScanAccess()
        {
            int y = START_Y;

            // ── Step 17 ───────────────────────────────────────────────
            Controls.Add(MakeSectionHeader("Step 17 — Printers", y)); y += 32;
            Controls.Add(MakeLabel("17) Printers required?", y));
            _grp17 = MakeRPanel(y, "Yes", "No", out _rb17Yes, out _rb17No);
            Controls.Add(_grp17); y += ROW_HEIGHT;

            // 17a: label on its own row, checkboxes below it with proper spacing
            Controls.Add(MakeLabel("17a) Which printers?", y)); y += 26;
            int px = COL_FIELD_X;
            _chk17Main       = MakeWideCheckBox("Main",       px);        px += 90;
            _chk17Stillwater = MakeWideCheckBox("Stillwater", px);        px += 100;
            _chk17Ironworks  = MakeWideCheckBox("Ironworks",  px);        px += 100;
            _chk17Other      = MakeWideCheckBox("Other",      px);
            PlaceCheckBoxRow(y, _chk17Main, _chk17Stillwater, _chk17Ironworks, _chk17Other);
            y += ROW_HEIGHT;

            // ── Step 18 ───────────────────────────────────────────────
            Controls.Add(MakeDivider(y)); y += 12;
            Controls.Add(MakeLabel("Step 18 — Scan to folder?", y));
            _grp18 = MakeRPanel(y, "Yes", "No", out _rb18Yes, out _rb18No);
            Controls.Add(_grp18); y += ROW_HEIGHT;

            Controls.Add(MakeLabel("18a) Which scanners?", y)); y += 26;
            px = COL_FIELD_X;
            _chk18Main       = MakeWideCheckBox("Main",       px);        px += 90;
            _chk18Stillwater = MakeWideCheckBox("Stillwater", px);        px += 100;
            _chk18Ironworks  = MakeWideCheckBox("Ironworks",  px);        px += 100;
            _chk18Other      = MakeWideCheckBox("Other",      px);
            PlaceCheckBoxRow(y, _chk18Main, _chk18Stillwater, _chk18Ironworks, _chk18Other);
            y += ROW_HEIGHT;

            // ── Step 19 — Mapped Drives ───────────────────────────────
            Controls.Add(MakeDivider(y)); y += 12;
            Controls.Add(MakeSectionHeader("Step 19 — Mapped Drives", y)); y += 32;

            // Widen to 140px so "(All Office)" and "(EX Office)" don't clip
            _chk19R = MakeDriveCheckBox("R (All Office)", COL_FIELD_X,       y);
            _chk19Q = MakeDriveCheckBox("Q (EX Office)",  COL_FIELD_X + 155, y);
            Controls.Add(_chk19R); Controls.Add(_chk19Q); y += 28;

            _chk19K = MakeDriveCheckBox("K (UserData)",   COL_FIELD_X,       y);
            _chk19S = MakeDriveCheckBox("S (Scan)",       COL_FIELD_X + 155, y);
            Controls.Add(_chk19K); Controls.Add(_chk19S); y += ROW_HEIGHT;

            // ── Step 20 — Shared Folders ──────────────────────────────
            Controls.Add(MakeDivider(y)); y += 12;
            Controls.Add(MakeSectionHeader("Step 20 — Shared Folder Access", y)); y += 28;
            Controls.Add(MakeNoteLabel("AD Groups — do not assign user directly to folders", y)); y += 20;

            int cName = COL_FIELD_X, cR = COL_FIELD_X + 240, cQ = COL_FIELD_X + 300;
            Controls.Add(new Label { Text = "Folder", Location = new Point(cName, y), Size = new Size(230, 18), Font = AppFonts.Caption, ForeColor = AppColors.TextMuted, BackColor = Color.Transparent });
            Controls.Add(new Label { Text = "R:\\",   Location = new Point(cR, y),    Size = new Size(50, 18),  Font = AppFonts.Caption, ForeColor = AppColors.TextMuted, BackColor = Color.Transparent });
            Controls.Add(new Label { Text = "Q:\\",   Location = new Point(cQ, y),    Size = new Size(50, 18),  Font = AppFonts.Caption, ForeColor = AppColors.TextMuted, BackColor = Color.Transparent });
            y += 20;

            _chk20R = new CheckBox[FOLDERS.Length];
            _chk20Q = new CheckBox[FOLDERS.Length];
            for (int i = 0; i < FOLDERS.Length; i++)
            {
                Controls.Add(new Label { Text = FOLDERS[i], Location = new Point(cName, y + 3), Size = new Size(230, 20), Font = AppFonts.Body, ForeColor = AppColors.TextSecondary, BackColor = Color.Transparent });
                _chk20R[i] = AddGridCb(cR, y);
                _chk20Q[i] = AddGridCb(cQ, y);
                y += 26;
            }

            // Wire Step 19 R → check all Step 20 R boxes on click
            _chk19R.Click += OnDriveRClicked;
        }

        // ── Step 19 R click handler ───────────────────────────────────

        private void OnDriveRClicked(object sender, EventArgs e)
        {
            // Only act when being checked (turning ON = check all R folders)
            if (!_chk19R.Checked) return;
            foreach (var cb in _chk20R)
                cb.Checked = true;
        }

        // ── Layout helpers ────────────────────────────────────────────

        private CheckBox MakeWideCheckBox(string text, int x)
        {
            var cb = new CheckBox
            {
                Text      = text,
                Size      = new Size(90, 22),
                Location  = new Point(x, 0), // y set in PlaceCheckBoxRow
                BackColor = Color.Transparent,
                ForeColor = AppColors.TextSecondary,
                Font      = AppFonts.Body
            };
            cb.CheckedChanged += (s, e) => RaiseDataChanged();
            return cb;
        }

        private void PlaceCheckBoxRow(int y, params CheckBox[] boxes)
        {
            int x = COL_FIELD_X;
            int[] widths = { 90, 100, 100, 80 };
            for (int i = 0; i < boxes.Length; i++)
            {
                boxes[i].Location = new Point(x, y + 2);
                x += widths[i];
                Controls.Add(boxes[i]);
            }
        }

        private CheckBox MakeDriveCheckBox(string text, int x, int y)
        {
            var cb = new CheckBox
            {
                Text      = text,
                Location  = new Point(x, y + 2),
                Size      = new Size(145, 22),   // wide enough for "(All Office)"
                BackColor = Color.Transparent,
                ForeColor = AppColors.TextSecondary,
                Font      = AppFonts.Body
            };
            cb.CheckedChanged += (s, e) => RaiseDataChanged();
            return cb;
        }

        private CheckBox AddGridCb(int x, int y)
        {
            var cb = new CheckBox { Location = new Point(x + 12, y + 2), Size = new Size(20, 20), BackColor = Color.Transparent };
            cb.CheckedChanged += (s, e) => RaiseDataChanged();
            Controls.Add(cb);
            return cb;
        }

        private Panel MakeRPanel(int y, string l1, string l2, out RadioButton r1, out RadioButton r2)
        {
            var p = new Panel { Location = new Point(COL_FIELD_X, y), Size = new Size(200, 26), BackColor = Color.Transparent };
            r1 = new RadioButton { Text = l1, Location = new Point(0, 2),  Size = new Size(80, 22), BackColor = Color.Transparent, ForeColor = AppColors.TextSecondary, Font = AppFonts.Body };
            r2 = new RadioButton { Text = l2, Location = new Point(90, 2), Size = new Size(80, 22), BackColor = Color.Transparent, ForeColor = AppColors.TextSecondary, Font = AppFonts.Body };
            r2.Checked = true;
            r1.CheckedChanged += (s, e) => RaiseDataChanged();
            r2.CheckedChanged += (s, e) => RaiseDataChanged();
            p.Controls.Add(r1); p.Controls.Add(r2);
            return p;
        }

        // ── IWizardPage ───────────────────────────────────────────────

        public override void LoadData(OnboardingRecord r)
        {
            _loading = true;
            SetR(_rb17Yes, _rb17No, r.PrintersRequired);
            _chk17Main.Checked       = r.Printer17Main;
            _chk17Stillwater.Checked = r.Printer17Stillwater;
            _chk17Ironworks.Checked  = r.Printer17Ironworks;
            _chk17Other.Checked      = r.Printer17Other;
            SetR(_rb18Yes, _rb18No, r.ScanToFolder);
            _chk18Main.Checked       = r.Scanner18Main;
            _chk18Stillwater.Checked = r.Scanner18Stillwater;
            _chk18Ironworks.Checked  = r.Scanner18Ironworks;
            _chk18Other.Checked      = r.Scanner18Other;
            _chk19R.Checked = r.DriveR; _chk19Q.Checked = r.DriveQ;
            _chk19K.Checked = r.DriveK; _chk19S.Checked = r.DriveS;
            for (int i = 0; i < FOLDERS.Length; i++)
            {
                _chk20R[i].Checked = r.SharedFolderR.Contains(FOLDERS[i]);
                _chk20Q[i].Checked = r.SharedFolderQ.Contains(FOLDERS[i]);
            }
            _loading = false;
        }

        public override OnboardingRecord SaveData(OnboardingRecord r)
        {
            r.PrintersRequired    = _rb17Yes.Checked;
            r.Printer17Main       = _chk17Main.Checked;
            r.Printer17Stillwater = _chk17Stillwater.Checked;
            r.Printer17Ironworks  = _chk17Ironworks.Checked;
            r.Printer17Other      = _chk17Other.Checked;
            r.ScanToFolder        = _rb18Yes.Checked;
            r.Scanner18Main       = _chk18Main.Checked;
            r.Scanner18Stillwater = _chk18Stillwater.Checked;
            r.Scanner18Ironworks  = _chk18Ironworks.Checked;
            r.Scanner18Other      = _chk18Other.Checked;
            r.DriveR = _chk19R.Checked; r.DriveQ = _chk19Q.Checked;
            r.DriveK = _chk19K.Checked; r.DriveS = _chk19S.Checked;
            r.SharedFolderR.Clear(); r.SharedFolderQ.Clear();
            for (int i = 0; i < FOLDERS.Length; i++)
            {
                if (_chk20R[i].Checked) r.SharedFolderR.Add(FOLDERS[i]);
                if (_chk20Q[i].Checked) r.SharedFolderQ.Add(FOLDERS[i]);
            }
            return r;
        }

        private void SetR(RadioButton r1, RadioButton r2, bool v) { r1.Checked = v; r2.Checked = !v; }
    }
}
