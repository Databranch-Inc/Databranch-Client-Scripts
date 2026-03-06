// =============================================================
// ArnotOnboarding — SettingsView.cs
// Version    : 1.5.0.0
// Author     : Sam Kirsch
// Company    : Databranch
// Created    : 2026-02-27
// Description: Settings page — allows editing of all app settings
//              including the two-segment HR export path with a
//              live preview of the full constructed path.
// =============================================================

using System;
using System.Drawing;
using System.IO;
using System.Windows.Forms;
using ArnotOnboarding.Managers;
using ArnotOnboarding.Models;
using ArnotOnboarding.Theme;

namespace ArnotOnboarding.Views
{
    public partial class SettingsView : UserControl
    {
        private readonly AppSettingsManager _mgr;
        private AppSettings                 _s;

        // ── Path section controls ─────────────────────────────────────
        private TextBox _txtBasePath;
        private TextBox _txtSubPath;
        private Label   _lblPathPreview;
        private Label   _lblBaseStatus;       // accessible / not found
        private Label   _lblBaseValidation;   // illegal characters warning
        private Label   _lblSubValidation;    // illegal characters warning
        private Button  _btnBrowseBase;

        // ── Email section controls ────────────────────────────────────
        private TextBox _txtEmail1;
        private TextBox _txtEmail2;

        // ── Auto-save ─────────────────────────────────────────────────
        private NumericUpDown _nudDebounce;

        // ── Status bar ────────────────────────────────────────────────
        private Label  _lblStatus;
        private Button _btnSave;
        private Button _btnReset;

        public SettingsView()
        {
            InitializeComponent();
            _mgr = AppSettingsManager.Instance;
            _s   = _mgr.Settings;
            ThemeHelper.ApplyTheme(this);
            BuildLayout();
            LoadValues();
        }

        // ── Layout ───────────────────────────────────────────────────

        private void BuildLayout()
        {
            this.Dock      = DockStyle.Fill;
            this.BackColor = AppColors.SurfaceBase;
            this.Padding   = new Padding(28, 20, 28, 16);

            // Master scroll panel so content survives small windows
            var scroll = new Panel
            {
                Dock          = DockStyle.Fill,
                AutoScroll    = true,
                BackColor     = Color.Transparent
            };

            int y = 0;

            // ── Page title ────────────────────────────────────────────
            var lblTitle = new Label
            {
                Text      = "Settings",
                Font      = AppFonts.Heading2,
                ForeColor = AppColors.TextPrimary,
                BackColor = Color.Transparent,
                AutoSize  = true,
                Location  = new Point(0, y)
            };
            scroll.Controls.Add(lblTitle);
            y += 42;

            // ══ SECTION: HR Export Path ═══════════════════════════════
            scroll.Controls.Add(MakeSectionHeader("HR Export Path", y)); y += 30;
            scroll.Controls.Add(MakeNote(
                "Files are saved to:  {Base Path} \\ {LastName, FirstName} \\ {Sub-Path}", y));
            y += 22;

            // Base path row
            scroll.Controls.Add(MakeFieldLabel("Base Path  (before employee folder)", y));
            _txtBasePath = MakeTextBox(y, 440);
            _txtBasePath.TextChanged += OnPathChanged;
            scroll.Controls.Add(_txtBasePath);

            _btnBrowseBase = new Button
            {
                Text     = "Browse…",
                Location = new Point(_txtBasePath.Right + 8, y + 22),
                Size     = new Size(72, 26),
                Font     = AppFonts.BodySmall
            };
            ThemeHelper.ApplyButtonStyle(_btnBrowseBase, ThemeHelper.ButtonStyle.Ghost);
            _btnBrowseBase.Click += OnBrowseBase;
            scroll.Controls.Add(_btnBrowseBase);

            _lblBaseStatus = new Label
            {
                Text      = string.Empty,
                Location  = new Point(_btnBrowseBase.Right + 10, y + 27),
                Size      = new Size(200, 18),
                Font      = AppFonts.Caption,
                BackColor = Color.Transparent
            };
            scroll.Controls.Add(_lblBaseStatus);

            _lblBaseValidation = new Label
            {
                Text      = string.Empty,
                Location  = new Point(0, y + 52),
                Size      = new Size(560, 16),
                Font      = AppFonts.Caption,
                ForeColor = AppColors.StatusError,
                BackColor = Color.Transparent
            };
            scroll.Controls.Add(_lblBaseValidation);
            y += 74;

            // Employee folder illustration
            var lblPivot = new Label
            {
                Text      = "          └──  {LastName, FirstName}  (auto-generated from employee name)",
                Location  = new Point(0, y),
                Size      = new Size(560, 18),
                Font      = AppFonts.Caption,
                ForeColor = AppColors.TextDim,
                BackColor = Color.Transparent
            };
            scroll.Controls.Add(lblPivot);
            y += 26;

            // Sub-path row
            scroll.Controls.Add(MakeFieldLabel("Sub-Path  (after employee folder)", y));
            _txtSubPath = MakeTextBox(y, 440);
            _txtSubPath.TextChanged += OnPathChanged;
            scroll.Controls.Add(_txtSubPath);

            _lblSubValidation = new Label
            {
                Text      = string.Empty,
                Location  = new Point(0, y + 52),
                Size      = new Size(560, 16),
                Font      = AppFonts.Caption,
                ForeColor = AppColors.StatusError,
                BackColor = Color.Transparent
            };
            scroll.Controls.Add(_lblSubValidation);
            y += 74;

            // Live preview
            scroll.Controls.Add(MakeFieldLabel("Full Path Preview", y));
            _lblPathPreview = new Label
            {
                Text      = string.Empty,
                Location  = new Point(0, y + 22),
                Size      = new Size(620, 36),
                Font      = new Font("Consolas", 8.5f),
                ForeColor = AppColors.BrandBlue,
                BackColor = AppColors.SurfaceVoid,
                Padding   = new Padding(6, 4, 6, 4),
                BorderStyle = BorderStyle.FixedSingle,
                AutoEllipsis = true
            };
            scroll.Controls.Add(_lblPathPreview);
            y += 68;

            scroll.Controls.Add(MakeDivider(y)); y += 18;

            // ══ SECTION: Email Notification Recipients ════════════════
            scroll.Controls.Add(MakeSectionHeader("Email Notification Recipients", y)); y += 30;
            scroll.Controls.Add(MakeNote(
                "These addresses receive the Outlook notification email on finalization.", y));
            y += 22;

            scroll.Controls.Add(MakeFieldLabel("Primary (To:)", y));
            _txtEmail1 = MakeTextBox(y, 300);
            scroll.Controls.Add(_txtEmail1);
            y += 58;

            scroll.Controls.Add(MakeFieldLabel("Secondary (CC:)", y));
            _txtEmail2 = MakeTextBox(y, 300);
            scroll.Controls.Add(_txtEmail2);
            y += 58;

            scroll.Controls.Add(MakeDivider(y)); y += 18;

            // ══ SECTION: Auto-Save ════════════════════════════════════
            scroll.Controls.Add(MakeSectionHeader("Auto-Save", y)); y += 30;
            scroll.Controls.Add(MakeNote(
                "Delay (in milliseconds) after the last keystroke before auto-saving a draft.", y));
            y += 22;

            scroll.Controls.Add(MakeFieldLabel("Debounce delay (ms)", y));
            _nudDebounce = new NumericUpDown
            {
                Location  = new Point(0, y + 22),
                Size      = new Size(110, 26),
                Minimum   = 200,
                Maximum   = 5000,
                Increment = 50,
                Font      = AppFonts.Body,
                BackColor = AppColors.SurfaceVoid,
                ForeColor = AppColors.TextPrimary,
                BorderStyle = BorderStyle.FixedSingle
            };
            scroll.Controls.Add(_nudDebounce);
            y += 58;

            scroll.Controls.Add(MakeDivider(y)); y += 18;

            // ══ SECTION: App Data ═════════════════════════════════════
            scroll.Controls.Add(MakeSectionHeader("Application Data", y)); y += 30;

            var lblAppData = new Label
            {
                Text      = $"Settings stored in:  {AppSettingsManager.AppDataRoot}",
                Location  = new Point(0, y),
                Size      = new Size(620, 18),
                Font      = AppFonts.Caption,
                ForeColor = AppColors.TextDim,
                BackColor = Color.Transparent
            };
            scroll.Controls.Add(lblAppData);
            y += 22;

            var btnOpenAppData = new Button
            {
                Text     = "Open App Data Folder",
                Location = new Point(0, y),
                Size     = new Size(160, 28),
                Font     = AppFonts.BodySmall
            };
            ThemeHelper.ApplyButtonStyle(btnOpenAppData, ThemeHelper.ButtonStyle.Ghost);
            btnOpenAppData.Click += (s, e) =>
            {
                try { System.Diagnostics.Process.Start("explorer.exe",
                    AppSettingsManager.AppDataRoot); }
                catch { }
            };
            scroll.Controls.Add(btnOpenAppData);
            y += 46;

            // ══ Bottom action bar ══════════════════════════════════════
            var bar = new Panel
            {
                Dock      = DockStyle.Bottom,
                Height    = 52,
                BackColor = AppColors.SurfaceRaised
            };
            bar.Paint += (s, e) =>
            {
                using (var p = new Pen(AppColors.BorderDefault))
                    e.Graphics.DrawLine(p, 0, 0, bar.Width, 0);
            };

            _btnSave = new Button
            {
                Text     = "Save Settings",
                Size     = new Size(130, 34),
                Location = new Point(8, 9),
                Font     = AppFonts.BodySmall
            };
            ThemeHelper.ApplyButtonStyle(_btnSave, ThemeHelper.ButtonStyle.Primary);
            _btnSave.Click += OnSave;

            _btnReset = new Button
            {
                Text     = "Reset to Defaults",
                Size     = new Size(140, 34),
                Location = new Point(146, 9),
                Font     = AppFonts.BodySmall
            };
            ThemeHelper.ApplyButtonStyle(_btnReset, ThemeHelper.ButtonStyle.Ghost);
            _btnReset.Click += OnReset;

            _lblStatus = new Label
            {
                Text      = string.Empty,
                Location  = new Point(296, 18),
                Size      = new Size(300, 18),
                Font      = AppFonts.Caption,
                ForeColor = AppColors.StatusSuccess,
                BackColor = Color.Transparent
            };

            bar.Controls.AddRange(new Control[] { _btnSave, _btnReset, _lblStatus });

            this.Controls.Add(scroll);
            this.Controls.Add(bar);
        }

        // ── Load / Save ───────────────────────────────────────────────

        private void LoadValues()
        {
            _txtBasePath.Text   = _s.HrBasePath;
            _txtSubPath.Text    = _s.HrSubPath;
            _txtEmail1.Text     = _s.NotifyEmail1;
            _txtEmail2.Text     = _s.NotifyEmail2;
            _nudDebounce.Value  = Math.Max(200, Math.Min(5000, _s.AutoSaveDebounceMs));
            UpdatePathPreview();
            UpdateBaseStatus();
            UpdateSubValidation();
        }

        private void OnSave(object sender, EventArgs e)
        {
            // Guard: refuse to save invalid paths
            if (!IsValidWindowsPath(_txtBasePath.Text.Trim()) ||
                !IsValidWindowsPath(_txtSubPath.Text.Trim()))
            {
                _lblStatus.ForeColor = AppColors.StatusError;
                _lblStatus.Text      = "⚠  Fix invalid path characters before saving.";
                return;
            }

            _s.HrBasePath         = _txtBasePath.Text.TrimEnd('\\').TrimEnd('/').Trim();
            _s.HrSubPath          = _txtSubPath.Text.TrimStart('\\').TrimStart('/').Trim();
            _s.NotifyEmail1       = _txtEmail1.Text.Trim();
            _s.NotifyEmail2       = _txtEmail2.Text.Trim();
            _s.AutoSaveDebounceMs = (int)_nudDebounce.Value;

            _mgr.SaveSettings();

            _lblStatus.ForeColor = AppColors.StatusSuccess;
            _lblStatus.Text      = $"✓  Saved  {DateTime.Now:h:mm:ss tt}";
        }

        private void OnReset(object sender, EventArgs e)
        {
            var confirm = MessageBox.Show(
                "Reset all settings to their default values?\n\nThis cannot be undone.",
                "Reset Settings",
                MessageBoxButtons.OKCancel,
                MessageBoxIcon.Question);

            if (confirm != DialogResult.OK) return;

            _s.HrBasePath         = @"R:\66 Human Resources Q\666 Employee Files";
            _s.HrSubPath          = @"01 Employment\01 Hiring\04 Onboarding";
            _s.NotifyEmail1       = "support@databranch.com";
            _s.NotifyEmail2       = "help@databranch.com";
            _s.AutoSaveDebounceMs = 750;

            LoadValues();
            _mgr.SaveSettings();

            _lblStatus.ForeColor = AppColors.TextMuted;
            _lblStatus.Text      = "Settings reset to defaults.";
        }

        private void OnBrowseBase(object sender, EventArgs e)
        {
            using (var dlg = new FolderBrowserDialog())
            {
                dlg.Description         = "Select the HR employee files root folder";
                dlg.ShowNewFolderButton = true;
                if (Directory.Exists(_txtBasePath.Text))
                    dlg.SelectedPath = _txtBasePath.Text;

                if (dlg.ShowDialog() == DialogResult.OK)
                    _txtBasePath.Text = dlg.SelectedPath;
            }
        }

        // ── Live preview & validation ─────────────────────────────────

        private void OnPathChanged(object sender, EventArgs e)
        {
            UpdatePathPreview();
            UpdateBaseStatus();
            UpdateSubValidation();
            UpdateSubValidation();
        }

        private void UpdatePathPreview()
        {
            string basePath = _txtBasePath.Text.TrimEnd('\\').Trim();
            string sub      = _txtSubPath.Text.TrimStart('\\').Trim();
            string preview  = Path.Combine(basePath, "Doe, Jane", sub);
            _lblPathPreview.Text = preview;
        }

        private static readonly char[] _illegalPathChars =
            System.IO.Path.GetInvalidPathChars();

        private bool IsValidWindowsPath(string path)
        {
            if (string.IsNullOrWhiteSpace(path)) return true;
            return path.IndexOfAny(_illegalPathChars) < 0;
        }

        private void UpdateBaseStatus()
        {
            string path = _txtBasePath.Text.Trim();

            // Check for illegal characters first
            if (!IsValidWindowsPath(path))
            {
                _lblBaseValidation.Text  = "⚠  Contains an invalid character for a Windows path";
                _lblBaseStatus.Text      = string.Empty;
                return;
            }
            _lblBaseValidation.Text = string.Empty;

            if (string.IsNullOrWhiteSpace(path))
            {
                _lblBaseStatus.Text = string.Empty;
                return;
            }

            if (Directory.Exists(path))
            {
                _lblBaseStatus.ForeColor = AppColors.StatusSuccess;
                _lblBaseStatus.Text      = "✓  Path accessible";
            }
            else
            {
                _lblBaseStatus.ForeColor = AppColors.TextMuted;
                _lblBaseStatus.Text      = "–  Path not found (will be created on export)";
            }
        }

        private void UpdateSubValidation()
        {
            string sub = _txtSubPath.Text.Trim();
            if (!IsValidWindowsPath(sub))
                _lblSubValidation.Text = "⚠  Contains an invalid character for a Windows path";
            else
                _lblSubValidation.Text = string.Empty;
        }

        // ── Widget helpers ────────────────────────────────────────────

        private Label MakeSectionHeader(string text, int y)
            => new Label
            {
                Text      = text,
                Location  = new Point(0, y),
                Size      = new Size(620, 22),
                Font      = AppFonts.LabelBold,
                ForeColor = AppColors.BrandRed,
                BackColor = Color.Transparent
            };

        private Label MakeNote(string text, int y)
            => new Label
            {
                Text      = text,
                Location  = new Point(0, y),
                Size      = new Size(620, 16),
                Font      = AppFonts.Caption,
                ForeColor = AppColors.TextDim,
                BackColor = Color.Transparent
            };

        private Label MakeFieldLabel(string text, int y)
            => new Label
            {
                Text      = text,
                Location  = new Point(0, y),
                Size      = new Size(620, 18),
                Font      = AppFonts.Caption,
                ForeColor = AppColors.TextMuted,
                BackColor = Color.Transparent
            };

        private TextBox MakeTextBox(int y, int width)
            => new TextBox
            {
                Location    = new Point(0, y + 22),
                Size        = new Size(width, 26),
                BackColor   = AppColors.SurfaceVoid,
                ForeColor   = AppColors.TextPrimary,
                BorderStyle = BorderStyle.FixedSingle,
                Font        = AppFonts.Body
            };

        private Panel MakeDivider(int y)
        {
            var p = new Panel
            {
                Location  = new Point(0, y),
                Size      = new Size(620, 1),
                BackColor = AppColors.BorderSubtle
            };
            return p;
        }
    }
}
