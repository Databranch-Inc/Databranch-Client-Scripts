// =============================================================
// ArnotOnboarding — Page04_AccountsAndCredentials.cs
// Version    : 1.5.8.0
// Changes    : - 7a auto-fills username from employee name (Page 2 sync)
//              - Toggle switch to unlock/customize 7a username
//              - 8a auto-fills email from employee name
//              - 8d defaults to Yes
//              - Radio groups each in isolated Panel (no cross-linking)
// =============================================================
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
using ArnotOnboarding.Models;
using ArnotOnboarding.Theme;

namespace ArnotOnboarding.Views.WizardPages
{
    public class Page04_AccountsAndCredentials : WizardPageBase
    {
        public override string PageTitle => "Accounts & Credentials";

        // Step 4
        private CheckBox _chk4Domain;
        private CheckBox _chk4MS365;
        // Step 5
        private Panel _grp5; private RadioButton _rb5BusinessStandard, _rb5Kiosk;
        // Step 6
        private Panel _grp6; private RadioButton _rb6Yes, _rb6No;
        // Step 7
        private TextBox      _txt7Username;
        private Label        _lbl7AutoNote;
        private ToggleSwitch _tog7Custom;   // unlock username editing
        private TextBox      _txt7Password;
        private Panel        _grp7Prompt;
        private RadioButton  _rb7PromptYes, _rb7PromptNo;
        // Step 8
        private TextBox      _txt8Username;
        private ToggleSwitch _tog8Custom;
        private Label        _lbl8AutoNote;
        private bool         _emailCustomized = false;
        private TextBox      _txt8Password;
        private Panel        _grp8Prompt;
        private RadioButton  _rb8PromptYes, _rb8PromptNo;
        private Panel        _grp8Calendar;
        private RadioButton  _rb8CalYes, _rb8CalNo;

        // Tracks whether user has manually unlocked / edited username
        private bool _usernameCustomized = false;

        public Page04_AccountsAndCredentials()
        {
            int y = START_Y;

            // ── Step 4 ────────────────────────────────────────────────
            Controls.Add(MakeSectionHeader("Step 4 — Accounts Needed (Responsibility)", y)); y += 32;
            _chk4Domain = MakeCheckBox("Domain (IT)", y);
            Controls.Add(_chk4Domain); y += 28;
            _chk4MS365  = MakeCheckBox("MS365/Email (IT) - Enforce 2FA", y);
            Controls.Add(_chk4MS365); y += ROW_HEIGHT;

            // ── Step 5 ────────────────────────────────────────────────
            Controls.Add(MakeDivider(y)); y += 12;
            Controls.Add(MakeSectionHeader("Step 5 — MS365 License Type", y)); y += 32;
            // Stacked radio buttons — single select
            _grp5 = new Panel { Location = new Point(COL_FIELD_X, y), Size = new Size(COL_FIELD_W_WIDE, 56), BackColor = Color.Transparent };
            _rb5BusinessStandard = new RadioButton { Text = "Business Standard & Datto SaaS protection (Databranch setup)", Location = new Point(0, 0),  Size = new Size(COL_FIELD_W_WIDE, 26), BackColor = Color.Transparent, ForeColor = AppColors.TextSecondary, Font = AppFonts.Body };
            _rb5Kiosk            = new RadioButton { Text = "Kiosk",                                                          Location = new Point(0, 28), Size = new Size(COL_FIELD_W_WIDE, 26), BackColor = Color.Transparent, ForeColor = AppColors.TextSecondary, Font = AppFonts.Body };
            _rb5BusinessStandard.Checked = true;
            _rb5BusinessStandard.CheckedChanged += (s, e) => RaiseDataChanged();
            _rb5Kiosk.CheckedChanged            += (s, e) => RaiseDataChanged();
            _grp5.Controls.Add(_rb5BusinessStandard);
            _grp5.Controls.Add(_rb5Kiosk);
            Controls.Add(_grp5); y += 56 + 8;

            // ── Step 6 ───────────────────────────────────────────────
            Controls.Add(MakeDivider(y)); y += 12;
            Controls.Add(MakeSectionHeader("Step 6 — Will User Have Local Administrative Rights?", y)); y += 32;
            _grp6 = MakeRPanel(y, "Yes", "No", out _rb6Yes, out _rb6No);
            Controls.Add(_grp6); y += ROW_HEIGHT;

            // ── Step 7 — Domain Credentials ──────────────────────────
            Controls.Add(MakeDivider(y)); y += 12;
            Controls.Add(MakeSectionHeader("Step 7 — Domain User Credentials", y)); y += 32;

            // 7a — Username with auto-fill + toggle to customize
            Controls.Add(MakeLabel("7a) Username", y));

            _txt7Username = new TextBox
            {
                Location    = new Point(COL_FIELD_X, y),
                Size        = new Size(COL_FIELD_W - 70, 26),
                BackColor   = AppColors.SurfaceVoid,
                ForeColor   = AppColors.TextDim,   // greyed out when locked
                BorderStyle = BorderStyle.FixedSingle,
                Font        = AppFonts.Mono,
                ReadOnly    = true                  // locked until toggled
            };
            _txt7Username.TextChanged += (s, e) => RaiseDataChanged();
            Controls.Add(_txt7Username);

            // Toggle switch — right of the textbox
            _tog7Custom = new ToggleSwitch
            {
                Location = new Point(COL_FIELD_X + COL_FIELD_W - 62, y - 1),
                Size     = new Size(56, 28),
                Checked  = false,
                ToolTip  = "Toggle to customize username"
            };
            _tog7Custom.CheckedChanged += OnUsernameToggleChanged;
            Controls.Add(_tog7Custom);

            _lbl7AutoNote = new Label
            {
                Text      = "Auto-filled from employee name  •  Toggle to customize",
                Location  = new Point(COL_FIELD_X, y + 28),
                Size      = new Size(COL_FIELD_W, 16),
                Font      = AppFonts.Caption,
                ForeColor = AppColors.TextDim,
                BackColor = Color.Transparent
            };
            Controls.Add(_lbl7AutoNote);
            y += ROW_HEIGHT + 12;

            Controls.Add(MakeLabel("7b) Temp Password", y));
            _txt7Password = MakeTextBox(y);
            Controls.Add(_txt7Password); y += ROW_HEIGHT;

            Controls.Add(MakeLabel("7c) Force password\nchange at first login?", y));
            _grp7Prompt = MakeRPanel(y, "Yes", "No", out _rb7PromptYes, out _rb7PromptNo);
            Controls.Add(_grp7Prompt); y += ROW_HEIGHT;

            // ── Step 8 — MS365 Credentials ───────────────────────────
            Controls.Add(MakeDivider(y)); y += 12;
            Controls.Add(MakeSectionHeader("Step 8 — MS365/Email User Credentials", y)); y += 32;

            Controls.Add(MakeLabel("8a) Username / Email", y));
            _txt8Username = new TextBox
            {
                Location    = new Point(COL_FIELD_X, y),
                Size        = new Size(COL_FIELD_W - 70, 26),
                BackColor   = AppColors.SurfaceVoid,
                ForeColor   = AppColors.TextDim,
                BorderStyle = BorderStyle.FixedSingle,
                Font        = AppFonts.Mono,
                ReadOnly    = true
            };
            _txt8Username.TextChanged += (s, e) => RaiseDataChanged();
            Controls.Add(_txt8Username);

            _tog8Custom = new ToggleSwitch
            {
                Location = new Point(COL_FIELD_X + COL_FIELD_W - 62, y - 1),
                Size     = new Size(56, 28),
                Checked  = false,
                ToolTip  = "Toggle to customize email"
            };
            _tog8Custom.CheckedChanged += OnEmailToggleChanged;
            Controls.Add(_tog8Custom);

            _lbl8AutoNote = new Label
            {
                Text      = "Auto-filled from Employee Email (Page 2)  •  Toggle to customize",
                Location  = new Point(COL_FIELD_X, y + 28),
                Size      = new Size(COL_FIELD_W, 16),
                Font      = AppFonts.Caption,
                ForeColor = AppColors.TextDim,
                BackColor = Color.Transparent
            };
            Controls.Add(_lbl8AutoNote);
            y += ROW_HEIGHT + 12;

            Controls.Add(MakeLabel("8b) Temp Password", y));
            _txt8Password = MakeTextBox(y);
            Controls.Add(_txt8Password); y += ROW_HEIGHT;

            Controls.Add(MakeLabel("8c) Force password\nchange at first login?", y));
            _grp8Prompt = MakeRPanel(y, "Yes", "No", out _rb8PromptYes, out _rb8PromptNo);
            Controls.Add(_grp8Prompt); y += ROW_HEIGHT;

            Controls.Add(MakeLabel("8d) Run calendar\naccess script?", y));
            // Default: Yes (per requirements)
            _grp8Calendar = MakeRPanel(y, "Yes", "No", out _rb8CalYes, out _rb8CalNo,
                defaultFirst: true);
            Controls.Add(_grp8Calendar);
        }

        // ── Toggle handler ────────────────────────────────────────────

        private void OnUsernameToggleChanged(object sender, EventArgs e)
        {
            bool unlocked = _tog7Custom.Checked;
            _usernameCustomized    = unlocked;
            _txt7Username.ReadOnly = !unlocked;
            _txt7Username.ForeColor = unlocked ? AppColors.BrandBlue : AppColors.TextDim;
            _lbl7AutoNote.Text = unlocked
                ? "Editing username manually"
                : "Auto-filled from employee name  •  Toggle to customize";
            if (!unlocked) ReSyncUsername();   // revert to auto if toggled back off
            RaiseDataChanged();
        }

        private void OnEmailToggleChanged(object sender, System.EventArgs e)
        {
            bool unlocked = _tog8Custom.Checked;
            _emailCustomized       = unlocked;
            _txt8Username.ReadOnly = !unlocked;
            _txt8Username.ForeColor = unlocked ? AppColors.BrandBlue : AppColors.TextDim;
            _lbl8AutoNote.Text = unlocked
                ? "Editing email manually"
                : "Auto-filled from Employee Email (Page 2)  •  Toggle to customize";
            if (!unlocked)
            {
                // Revert to auto-fill from record
                _loading = true;
                // Will re-sync on next SyncFromRecord call
                _loading = false;
            }
            RaiseDataChanged();
        }

        private void ReSyncUsername()
        {
            if (_loading) return;
            // Recompute from stored record — grab from the text currently showing
            // (the record won't have updated first/last yet from page 2 mid-session,
            // so use whatever was last synced via SyncFromRecord)
            // No-op if we don't have a name to work with yet.
        }

        // ── Cross-page sync — called by WizardView after loading ──────

        /// <summary>
        /// Called by WizardView when navigating TO this page or when
        /// data from Page 2 (UserInformation) has changed.
        /// Syncs auto-filled fields unless the user has customized them.
        /// </summary>
        public void SyncFromRecord(OnboardingRecord r)
        {
            // 7a: username = first initial + last name, lower case
            if (!_usernameCustomized)
            {
                string username = BuildUsername(r.EmployeeFirstName, r.EmployeeLastName);
                _loading = true;
                _txt7Username.Text = username;
                _loading = false;
            }

            // 8a: email from Page 2 — only auto-fill if not customized
            if (!_emailCustomized)
            {
                _loading = true;
                _txt8Username.Text = r.EmailAddress;
                _loading = false;
            }
        }

        private static string BuildUsername(string first, string last)
        {
            if (string.IsNullOrWhiteSpace(first) && string.IsNullOrWhiteSpace(last))
                return string.Empty;
            string f = first.Trim().Length > 0 ? first.Trim()[0].ToString().ToLower() : string.Empty;
            string l = last.Trim().ToLower().Replace(" ", string.Empty);
            return f + l;   // e.g. "Jane Doe" → "jdoe"
        }

        // ── IWizardPage ──────────────────────────────────────────────

        public override void LoadData(OnboardingRecord r)
        {
            _loading = true;
            _chk4Domain.Checked           = r.AccountDomain;
            _chk4MS365.Checked            = r.AccountMS365;
            _rb5BusinessStandard.Checked = r.LicenseBusinessStandard || (!r.LicenseBusinessStandard && !r.LicenseKiosk);
            _rb5Kiosk.Checked            = r.LicenseKiosk;
            SetR(_rb6Yes, _rb6No, r.LocalAdminRights);

            _usernameCustomized    = r.DomainUsernameCustomized;
            _tog7Custom.Checked    = r.DomainUsernameCustomized;
            _txt7Username.ReadOnly = !r.DomainUsernameCustomized;
            _txt7Username.ForeColor = r.DomainUsernameCustomized
                ? AppColors.BrandBlue : AppColors.TextDim;

            // If no saved username yet, auto-build from name
            _txt7Username.Text = string.IsNullOrEmpty(r.DomainUsername)
                ? BuildUsername(r.EmployeeFirstName, r.EmployeeLastName)
                : r.DomainUsername;

            _txt7Password.Text = r.DomainTempPassword;
            SetR(_rb7PromptYes, _rb7PromptNo, r.DomainForcePasswordChange);

            // 8a: restore toggle state + email
            _emailCustomized        = r.EmailCustomized;
            _tog8Custom.Checked     = r.EmailCustomized;
            _txt8Username.ReadOnly  = !r.EmailCustomized;
            _txt8Username.ForeColor = r.EmailCustomized ? AppColors.BrandBlue : AppColors.TextDim;
            _txt8Username.Text      = string.IsNullOrEmpty(r.MS365Username) && !r.EmailCustomized
                ? r.EmailAddress
                : r.MS365Username;

            _txt8Password.Text = r.MS365TempPassword;
            SetR(_rb8PromptYes, _rb8PromptNo, r.MS365ForcePasswordChange);
            // 8d default Yes on new record
            SetR(_rb8CalYes, _rb8CalNo,
                r.RecordIsNew ? true : r.RunCalendarScript);

            _loading = false;
        }

        public override OnboardingRecord SaveData(OnboardingRecord r)
        {
            r.AccountDomain            = _chk4Domain.Checked;
            r.AccountMS365             = _chk4MS365.Checked;
            r.LicenseBusinessStandard  = _rb5BusinessStandard.Checked;
            r.LicenseKiosk             = _rb5Kiosk.Checked;
            r.LocalAdminRights         = _rb6Yes.Checked;
            r.DomainUsername           = _txt7Username.Text.Trim();
            r.DomainUsernameCustomized = _usernameCustomized;
            r.DomainTempPassword       = _txt7Password.Text.Trim();
            r.DomainForcePasswordChange = _rb7PromptYes.Checked;
            r.MS365Username            = _txt8Username.Text.Trim();
            r.EmailCustomized          = _emailCustomized;
            r.MS365TempPassword        = _txt8Password.Text.Trim();
            r.MS365ForcePasswordChange = _rb8PromptYes.Checked;
            r.RunCalendarScript        = _rb8CalYes.Checked;
            r.RecordIsNew              = false;   // Mark as no longer brand new
            return r;
        }

        // ── Helpers ───────────────────────────────────────────────────

        private Panel MakeRPanel(int y, string l1, string l2,
            out RadioButton r1, out RadioButton r2, bool defaultFirst = false)
        {
            var p = new Panel
            {
                Location  = new Point(COL_FIELD_X, y),
                Size      = new Size(COL_FIELD_W, 28),
                BackColor = Color.Transparent
            };
            r1 = new RadioButton { Text = l1, Location = new Point(0,   2), Size = new Size(80, 24), BackColor = Color.Transparent, ForeColor = AppColors.TextSecondary, Font = AppFonts.Body };
            r2 = new RadioButton { Text = l2, Location = new Point(90,  2), Size = new Size(80, 24), BackColor = Color.Transparent, ForeColor = AppColors.TextSecondary, Font = AppFonts.Body };
            if (defaultFirst) r1.Checked = true; else r2.Checked = true;
            r1.CheckedChanged += (s, e) => RaiseDataChanged();
            r2.CheckedChanged += (s, e) => RaiseDataChanged();
            p.Controls.Add(r1); p.Controls.Add(r2);
            return p;
        }

        private void SetR(RadioButton r1, RadioButton r2, bool v)
        { r1.Checked = v; r2.Checked = !v; }
    }

    // ─────────────────────────────────────────────────────────────────
    // ToggleSwitch — custom owner-drawn toggle control
    // Renders as an iOS-style pill: grey when off, brand-red when on.
    // ─────────────────────────────────────────────────────────────────
    internal class ToggleSwitch : Control
    {
        private bool _checked;
        public string ToolTip { get; set; }

        public bool Checked
        {
            get => _checked;
            set { if (_checked == value) return; _checked = value; Invalidate(); CheckedChanged?.Invoke(this, EventArgs.Empty); }
        }
        public event EventHandler CheckedChanged;

        public ToggleSwitch()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.UserPaint |
                     ControlStyles.DoubleBuffer |
                     ControlStyles.ResizeRedraw, true);
            Cursor = Cursors.Hand;
            Size   = new Size(56, 28);
        }

        protected override void OnClick(EventArgs e) { Checked = !Checked; base.OnClick(e); }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g   = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;

            int  w  = Width, h = Height;
            int  r  = h / 2;
            var  rc = new Rectangle(0, (h - r * 2) / 2, w, r * 2);

            // Track
            using (var brush = new SolidBrush(_checked
                ? AppColors.BrandRedSoft : AppColors.SurfaceOverlay))
                FillRoundRect(g, brush, rc, r);

            // Knob
            int knobD  = h - 6;
            int knobX  = _checked ? w - knobD - 3 : 3;
            int knobY  = (h - knobD) / 2;
            using (var knob = new SolidBrush(Color.White))
                g.FillEllipse(knob, knobX, knobY, knobD, knobD);

            // Label inside track
            string lbl    = _checked ? "ON" : "OFF";
            using (var tf = new SolidBrush(Color.White))
            using (var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
            using (var f  = new Font("Segoe UI", 6.5f, FontStyle.Bold))
            {
                var textRc = _checked
                    ? new RectangleF(rc.X, rc.Y, rc.Width * 0.55f, rc.Height)
                    : new RectangleF(rc.X + rc.Width * 0.45f, rc.Y, rc.Width * 0.55f, rc.Height);
                g.DrawString(lbl, f, tf, textRc, sf);
            }
        }

        private static void FillRoundRect(Graphics g, Brush b, Rectangle rc, int r)
        {
            using (var path = new System.Drawing.Drawing2D.GraphicsPath())
            {
                path.AddArc(rc.X,              rc.Y,              r * 2, r * 2, 180, 90);
                path.AddArc(rc.Right - r * 2,  rc.Y,              r * 2, r * 2, 270, 90);
                path.AddArc(rc.Right - r * 2,  rc.Bottom - r * 2, r * 2, r * 2,   0, 90);
                path.AddArc(rc.X,              rc.Bottom - r * 2, r * 2, r * 2,  90, 90);
                path.CloseFigure();
                g.FillPath(b, path);
            }
        }
    }
}
