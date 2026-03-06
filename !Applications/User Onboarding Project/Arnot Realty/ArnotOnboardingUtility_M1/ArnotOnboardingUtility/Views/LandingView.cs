// =============================================================
// ArnotOnboardingUtility — Views/LandingView.cs
// Version    : 1.0.1.0
// Author     : Sam Kirsch / Databranch
// Created    : 2026-02-28
// Modified   : 2026-02-28
// Description: Landing screen. Two columns:
//   Left  — New Onboarding (file picker + validation)
//   Right — Continue (recent sessions list + file picker)
// DockStyle.Top panels added LAST so they stack correctly.
// =============================================================
using System;
using System.Drawing;
using System.IO;
using System.Windows.Forms;
using ArnotOnboardingUtility.Managers;
using ArnotOnboardingUtility.Models;
using ArnotOnboardingUtility.Theme;

namespace ArnotOnboardingUtility.Views
{
    public class LandingView : UserControl
    {
        public event EventHandler<SessionLoadEventArgs> OnNewOnboardingRequested;
        public event EventHandler<SessionLoadEventArgs> OnResumeSessionRequested;

        private ListView _sessionList;
        private Label    _statusLabel;

        public LandingView()
        {
            BackColor = AppColors.SurfaceBase;
            Dock      = DockStyle.Fill;
            BuildLayout();
            RefreshSessionList();
        }

        private void BuildLayout()
        {
            // ── Status bar (DockStyle.Bottom — add first so it docks to bottom) ──
            _statusLabel = new Label
            {
                Dock      = DockStyle.Bottom,
                Height    = 26,
                BackColor = AppColors.SurfaceRaised,
                ForeColor = AppColors.TextMuted,
                Font      = AppFonts.Caption,
                TextAlign = ContentAlignment.MiddleLeft,
                Padding   = new Padding(16, 0, 0, 0),
                Text      = "Select a finalized onboarding JSON to begin, or resume a saved session."
            };
            Controls.Add(_statusLabel);

            // ── Body (DockStyle.Fill — add before Top controls) ───────
            var body = new Panel
            {
                Dock      = DockStyle.Fill,
                BackColor = AppColors.SurfaceBase,
                Padding   = new Padding(32, 24, 32, 16)
            };
            Controls.Add(body);

            // ── Header (DockStyle.Top — add LAST so it stacks at top) ─
            var header = new Panel
            {
                Dock      = DockStyle.Top,
                Height    = 100,
                BackColor = AppColors.SurfaceVoid
            };
            header.Paint += (s, e) =>
            {
                var g = e.Graphics;
                g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
                using (var b = new SolidBrush(AppColors.BrandRedSoft))
                    g.DrawString("DATABRANCH  ·  ARNOT REALTY", AppFonts.NavEyebrow, b, 32, 22);
                using (var b = new SolidBrush(AppColors.TextPrimary))
                    g.DrawString("IT Onboarding Utility", AppFonts.Heading1, b, 32, 42);
                using (var pen = new Pen(AppColors.BorderSubtle))
                    g.DrawLine(pen, 0, header.Height - 1, header.Width, header.Height - 1);
            };
            Controls.Add(header);

            // ── Two-column layout inside body ──────────────────────────
            const int LEFT_W = 340;
            const int GAP    = 24;

            var leftCol = new Panel
            {
                BackColor = AppColors.SurfaceBase,
                Location  = new Point(0, 0),
                Size      = new Size(LEFT_W, 500),
                Anchor    = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Bottom
            };
            body.Controls.Add(leftCol);

            var rightCol = new Panel
            {
                BackColor = AppColors.SurfaceBase,
                Location  = new Point(LEFT_W + GAP, 0),
                Size      = new Size(500, 500),
                Anchor    = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom
            };
            body.Controls.Add(rightCol);

            body.Resize += (s, e) =>
            {
                int bodyH = body.ClientSize.Height - body.Padding.Top - body.Padding.Bottom;
                leftCol.Height  = bodyH;
                rightCol.Left   = LEFT_W + GAP;
                rightCol.Width  = body.ClientSize.Width - LEFT_W - GAP - body.Padding.Left - body.Padding.Right;
                rightCol.Height = bodyH;
            };

            BuildNewOnboardingCol(leftCol);
            BuildContinueCol(rightCol);
        }

        // ── Left column — New Onboarding ──────────────────────────────
        private void BuildNewOnboardingCol(Panel col)
        {
            var card = new Panel
            {
                BackColor = AppColors.SurfaceCard,
                Bounds    = new Rectangle(0, 0, 320, 300),
                Anchor    = AnchorStyles.Top | AnchorStyles.Left
            };
            card.Paint += (s, e) =>
            {
                using (var pen = new Pen(AppColors.BorderDefault))
                    e.Graphics.DrawRectangle(pen, 0, 0, card.Width - 1, card.Height - 1);
                using (var b = new SolidBrush(AppColors.BrandRedSoft))
                    e.Graphics.FillRectangle(b, 0, 0, 4, card.Height);
            };
            col.Controls.Add(card);

            int y = 20;
            void AddLbl(string text, Font font, Color color, int x = 16, int h = 20)
            {
                card.Controls.Add(new Label
                {
                    Text = text, Font = font, ForeColor = color,
                    BackColor = Color.Transparent, Bounds = new Rectangle(x, y, 288, h)
                });
                y += h + 4;
            }

            AddLbl("NEW ONBOARDING", AppFonts.NavSection, AppColors.TextDim);
            y += 4;
            AddLbl("Start a new workflow", AppFonts.Heading3, AppColors.TextPrimary, h: 24);
            y += 4;
            AddLbl("Select a finalized onboarding JSON", AppFonts.BodySmall, AppColors.TextSecondary);
            AddLbl("exported by the ArnotOnboarding", AppFonts.BodySmall, AppColors.TextSecondary);
            AddLbl("HR application to begin.", AppFonts.BodySmall, AppColors.TextSecondary);
            y += 8;

            card.Controls.Add(new Panel { Bounds = new Rectangle(16, y, 288, 1), BackColor = AppColors.BorderSubtle });
            y += 12;

            AddLbl("Requirements:", AppFonts.LabelBold, AppColors.TextMuted);
            AddLbl("• status = \"finalized\"", AppFonts.Caption, AppColors.TextMuted, x: 24);
            AddLbl("• schemaVersion = 1.3",   AppFonts.Caption, AppColors.TextMuted, x: 24);
            AddLbl("• Valid employee name fields", AppFonts.Caption, AppColors.TextMuted, x: 24);
            y += 8;

            var btn = new Button { Text = "Browse for JSON File…", Bounds = new Rectangle(12, y, 296, 34) };
            ThemeHelper.StyleAsPrimaryButton(btn);
            btn.Click += BtnBrowseNew_Click;
            card.Controls.Add(btn);

            card.Height = y + 50;
        }

        // ── Right column — Continue ───────────────────────────────────
        private void BuildContinueCol(Panel col)
        {
            col.Controls.Add(new Label
            {
                Text = "CONTINUE", Font = AppFonts.NavSection, ForeColor = AppColors.TextDim,
                BackColor = Color.Transparent, Bounds = new Rectangle(0, 0, 500, 18)
            });
            col.Controls.Add(new Label
            {
                Text = "Resume an existing session", Font = AppFonts.Heading3,
                ForeColor = AppColors.TextPrimary, BackColor = Color.Transparent,
                Bounds = new Rectangle(0, 22, 500, 24)
            });

            _sessionList = new ListView
            {
                Bounds        = new Rectangle(0, 54, 500, 300),
                View          = View.Details,
                FullRowSelect = true,
                GridLines     = false,
                HeaderStyle   = ColumnHeaderStyle.Nonclickable,
                BackColor     = AppColors.SurfaceCard,
                ForeColor     = AppColors.TextSecondary,
                BorderStyle   = BorderStyle.None,
                Font          = AppFonts.BodySmall,
                MultiSelect   = false,
                Anchor        = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom
            };
            _sessionList.Columns.Add("Employee",    180);
            _sessionList.Columns.Add("Type",         55);
            _sessionList.Columns.Add("Progress",    100);
            _sessionList.Columns.Add("Last Worked", 140);
            _sessionList.DoubleClick += (s, e) => TryResumeSelected();
            col.Controls.Add(_sessionList);

            // Resize list with column
            col.Resize += (s, e) =>
            {
                _sessionList.Width  = col.ClientSize.Width;
                _sessionList.Height = col.ClientSize.Height - 54 - 42;
            };

            int btnY = 362;
            var btnResume = new Button { Text = "Resume Selected", Bounds = new Rectangle(0, btnY, 155, 30) };
            ThemeHelper.StyleAsPrimaryButton(btnResume);
            btnResume.Click += (s, e) => TryResumeSelected();
            col.Controls.Add(btnResume);

            var btnBrowse = new Button { Text = "Browse for JSON…", Bounds = new Rectangle(163, btnY, 150, 30) };
            ThemeHelper.StyleAsGhostButton(btnBrowse);
            btnBrowse.Click += BtnBrowseNew_Click;
            col.Controls.Add(btnBrowse);

            var btnDelete = new Button { Text = "Remove Session", Bounds = new Rectangle(321, btnY, 140, 30) };
            ThemeHelper.StyleAsGhostButton(btnDelete);
            btnDelete.ForeColor = AppColors.StatusError;
            btnDelete.FlatAppearance.BorderColor = AppColors.StatusErrorBd;
            btnDelete.Click += BtnDelete_Click;
            col.Controls.Add(btnDelete);
        }

        // ── Session List ──────────────────────────────────────────────
        private void RefreshSessionList()
        {
            _sessionList.Items.Clear();
            var sessions = SessionManager.GetAllSessions();
            if (sessions.Count == 0)
            {
                var empty = new ListViewItem("No saved sessions found");
                empty.SubItems.Add("—"); empty.SubItems.Add("—"); empty.SubItems.Add("—");
                empty.ForeColor = AppColors.TextDim;
                _sessionList.Items.Add(empty);
                return;
            }
            foreach (var entry in sessions)
            {
                var item = new ListViewItem(entry.EmployeeName);
                item.SubItems.Add(entry.UserType);
                item.SubItems.Add(entry.ProgressDisplay);
                item.SubItems.Add(entry.LastWorkedDisplay);
                item.Tag       = entry;
                item.ForeColor = entry.IsComplete ? AppColors.StatusSuccess : AppColors.TextSecondary;
                _sessionList.Items.Add(item);
            }
        }

        // ── Event Handlers ────────────────────────────────────────────
        private void BtnBrowseNew_Click(object sender, EventArgs e)
        {
            using (var dlg = new OpenFileDialog())
            {
                dlg.Title       = "Select Onboarding JSON File";
                dlg.Filter      = "Onboarding Records (*.json)|*.json|All Files (*.*)|*.*";
                dlg.FilterIndex = 1;
                if (dlg.ShowDialog() != DialogResult.OK) return;
                TryLoadJson(dlg.FileName, isNew: true);
            }
        }

        private void TryResumeSelected()
        {
            if (_sessionList.SelectedItems.Count == 0) return;
            var entry = _sessionList.SelectedItems[0].Tag as SessionIndexEntry;
            if (entry == null) return;

            if (!File.Exists(entry.JsonSourcePath))
            {
                var r = MessageBox.Show(
                    $"Source JSON not found:\n{entry.JsonSourcePath}\n\nBrowse for it?",
                    "File Not Found", MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
                if (r == DialogResult.Yes) BtnBrowseNew_Click(null, EventArgs.Empty);
                return;
            }
            TryLoadJson(entry.JsonSourcePath, isNew: false);
        }

        private void BtnDelete_Click(object sender, EventArgs e)
        {
            if (_sessionList.SelectedItems.Count == 0) return;
            var entry = _sessionList.SelectedItems[0].Tag as SessionIndexEntry;
            if (entry == null) return;
            if (MessageBox.Show($"Remove saved session for {entry.EmployeeName}?",
                    "Remove Session", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            SessionManager.Delete(entry.RecordId);
            RefreshSessionList();
            SetStatus("Session removed.");
        }

        // ── JSON Load / Validate ──────────────────────────────────────
        private void TryLoadJson(string jsonPath, bool isNew)
        {
            SetStatus("Loading record…");
            Cursor = Cursors.WaitCursor;
            OnboardingRecord record = null;
            try
            {
                record = SessionManager.LoadOnboardingRecord(jsonPath);
            }
            catch (SchemaMismatchException smEx)
            {
                Cursor = Cursors.Default;
                var proceed = MessageBox.Show(
                    $"Schema version mismatch.\nExpected: 1.3   Found: {smEx.Record.SchemaVersion}\n\nContinue anyway?",
                    "Schema Warning", MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
                if (proceed != DialogResult.Yes) { SetStatus(""); return; }
                record = smEx.Record;
            }
            catch (Exception ex)
            {
                Cursor = Cursors.Default;
                MessageBox.Show(ex.Message, "Cannot Load Record", MessageBoxButtons.OK, MessageBoxIcon.Error);
                SetStatus(""); return;
            }
            finally { Cursor = Cursors.Default; }

            var steps   = StepCatalog.Build(record);
            var existing = SessionManager.Load(record.RecordId);
            EngineerSession session;

            if (existing != null)
            {
                var choice = MessageBox.Show(
                    $"A session exists for {record.FullName} (Step {existing.CurrentStepIndex + 1} of {existing.TotalSteps}).\nResume where you left off?",
                    "Existing Session", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
                if (choice == DialogResult.Yes)
                {
                    existing.JsonSourcePath = jsonPath;
                    existing.TotalSteps     = steps.Count;
                    SessionManager.Save(existing);
                    session = existing;
                }
                else
                {
                    SessionManager.Delete(record.RecordId);
                    session = SessionManager.CreateNew(record, jsonPath, steps);
                }
            }
            else
            {
                session = SessionManager.CreateNew(record, jsonPath, steps);
            }

            SetStatus($"Loaded — {record.FullName}");
            var args = new SessionLoadEventArgs(record, session);
            if (existing == null || isNew) OnNewOnboardingRequested?.Invoke(this, args);
            else                           OnResumeSessionRequested?.Invoke(this, args);
        }

        private void SetStatus(string text) => _statusLabel.Text = text;
    }
}
