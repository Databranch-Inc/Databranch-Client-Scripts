// =============================================================
// ArnotOnboarding — RecordLibraryView.cs
// Version    : 1.6.0.0
// Author     : Sam Kirsch
// Company    : Databranch
// Created    : 2026-02-27
// Modified   : 2026-02-28
// Description: Phase 4/5 — Past Records screen.
//              Lists all finalized onboarding records from the
//              local RecordIndex. Shows employee name, dept,
//              finalized date. Actions: open PDF, open folder,
//              re-open email. Also provides a Refresh button
//              that requeries the network share for records
//              created by other engineers.
//
// v1.6.0.0 — Restart Onboarding now goes through full lock
//             negotiation via DraftManager.RestartFromRecord.
//             - Blocked with clear message if locked by another user
//             - Stale lock prompts user to override or cancel
//             - Lock file errors show a warning but don't hard-block
//             - Grid shows lock status column (🔒 / —)
//             - UpdateButtons disables Restart if record is locked
//               by another user
// =============================================================

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Windows.Forms;
using ArnotOnboarding.Managers;
using ArnotOnboarding.Models;
using ArnotOnboarding.Theme;

namespace ArnotOnboarding.Views
{
    public partial class RecordLibraryView : UserControl
    {
        private readonly AppSettingsManager _appSettings;
        private List<RecordIndexEntry>       _entries = new List<RecordIndexEntry>();

        // Controls
        private Label        _lblTitle;
        private Label        _lblCount;
        private Button       _btnRefresh;
        private DataGridView _grid;
        private Panel        _actionBar;
        private Button       _btnOpenPdf;
        private Button       _btnOpenFolder;
        private Button       _btnResendEmail;
        private Button       _btnRestart;
        private Label        _lblStatus;

        public RecordLibraryView()
        {
            InitializeComponent();
            _appSettings = AppSettingsManager.Instance;
            ThemeHelper.ApplyTheme(this);
            BuildLayout();
            LoadRecords();
        }

        // ── Build UI ─────────────────────────────────────────────────

        private void BuildLayout()
        {
            this.Dock      = DockStyle.Fill;
            this.BackColor = AppColors.SurfaceBase;
            this.Padding   = new Padding(24, 20, 24, 16);

            // ── Top bar ───────────────────────────────────────────────
            var topBar = new Panel
            {
                Dock      = DockStyle.Top,
                Height    = 52,
                BackColor = Color.Transparent
            };

            _lblTitle = new Label
            {
                Text      = "Past Records",
                Font      = AppFonts.Heading2,
                ForeColor = AppColors.TextPrimary,
                BackColor = Color.Transparent,
                AutoSize  = true,
                Location  = new Point(0, 4)
            };

            _lblCount = new Label
            {
                Text      = string.Empty,
                Font      = AppFonts.Caption,
                ForeColor = AppColors.TextMuted,
                BackColor = Color.Transparent,
                AutoSize  = true,
                Location  = new Point(0, 34)
            };

            _btnRefresh = new Button
            {
                Text     = "⟳  Refresh from Network",
                Size     = new Size(180, 32),
                Location = new Point(0, 10),   // Right-aligned in OnLayout
                Font     = AppFonts.BodySmall
            };
            ThemeHelper.ApplyButtonStyle(_btnRefresh, ThemeHelper.ButtonStyle.Ghost);
            _btnRefresh.Click += OnRefreshClicked;

            topBar.Controls.AddRange(new Control[] { _lblTitle, _lblCount, _btnRefresh });

            // ── Action bar (bottom) ───────────────────────────────────
            _actionBar = new Panel
            {
                Dock      = DockStyle.Bottom,
                Height    = 52,
                BackColor = AppColors.SurfaceRaised
            };
            _actionBar.Paint += (s, e) =>
            {
                using (var pen = new Pen(AppColors.BorderDefault))
                    e.Graphics.DrawLine(pen, 0, 0, _actionBar.Width, 0);
            };

            _btnOpenPdf = new Button
            {
                Text     = "Open PDF",
                Size     = new Size(110, 34),
                Location = new Point(8, 9),
                Enabled  = false,
                Font     = AppFonts.BodySmall
            };
            ThemeHelper.ApplyButtonStyle(_btnOpenPdf, ThemeHelper.ButtonStyle.Primary);
            _btnOpenPdf.Click += OnOpenPdfClicked;

            _btnOpenFolder = new Button
            {
                Text     = "Open Folder",
                Size     = new Size(110, 34),
                Location = new Point(126, 9),
                Enabled  = false,
                Font     = AppFonts.BodySmall
            };
            ThemeHelper.ApplyButtonStyle(_btnOpenFolder, ThemeHelper.ButtonStyle.Secondary);
            _btnOpenFolder.Click += OnOpenFolderClicked;

            _btnResendEmail = new Button
            {
                Text     = "Re-send Email",
                Size     = new Size(120, 34),
                Location = new Point(244, 9),
                Enabled  = false,
                Font     = AppFonts.BodySmall
            };
            ThemeHelper.ApplyButtonStyle(_btnResendEmail, ThemeHelper.ButtonStyle.Ghost);
            _btnResendEmail.Click += OnResendEmailClicked;

            _btnRestart = new Button
            {
                Text     = "\u21BA  Restart Onboarding",
                Size     = new Size(160, 34),
                Location = new Point(372, 9),
                Enabled  = false,
                Font     = AppFonts.BodySmall
            };
            ThemeHelper.ApplyButtonStyle(_btnRestart, ThemeHelper.ButtonStyle.Secondary);
            _btnRestart.Click += OnRestartClicked;

            _lblStatus = new Label
            {
                Text      = string.Empty,
                Font      = AppFonts.Caption,
                ForeColor = AppColors.StatusSuccess,
                BackColor = Color.Transparent,
                AutoSize  = true,
                Location  = new Point(542, 19)
            };

            _actionBar.Controls.AddRange(new Control[]
                { _btnOpenPdf, _btnOpenFolder, _btnResendEmail, _btnRestart, _lblStatus });

            // ── Grid ──────────────────────────────────────────────────
            _grid = new DataGridView
            {
                Dock                    = DockStyle.Fill,
                BackgroundColor         = AppColors.SurfaceBase,
                GridColor               = AppColors.BorderSubtle,
                BorderStyle             = BorderStyle.None,
                RowHeadersVisible       = false,
                MultiSelect             = false,
                SelectionMode           = DataGridViewSelectionMode.FullRowSelect,
                AllowUserToAddRows      = false,
                AllowUserToDeleteRows   = false,
                AllowUserToResizeRows   = false,
                ReadOnly                = true,
                AutoSizeColumnsMode     = DataGridViewAutoSizeColumnsMode.Fill,
                ColumnHeadersHeightSizeMode =
                    DataGridViewColumnHeadersHeightSizeMode.DisableResizing,
                ColumnHeadersHeight     = 30,
                RowTemplate             = { Height = 28 },
                DefaultCellStyle        = new DataGridViewCellStyle
                {
                    BackColor          = AppColors.SurfaceBase,
                    ForeColor          = AppColors.TextSecondary,
                    Font               = AppFonts.Body,
                    SelectionBackColor = AppColors.SurfaceElevated,
                    SelectionForeColor = AppColors.TextPrimary
                },
                ColumnHeadersDefaultCellStyle = new DataGridViewCellStyle
                {
                    BackColor          = AppColors.SurfaceRaised,
                    ForeColor          = AppColors.TextMuted,
                    Font               = AppFonts.LabelBold,
                    SelectionBackColor = AppColors.SurfaceRaised,
                    SelectionForeColor = AppColors.TextMuted,
                    Padding            = new Padding(4, 0, 0, 0)
                },
                AlternatingRowsDefaultCellStyle = new DataGridViewCellStyle
                {
                    BackColor          = AppColors.SurfaceRaised,
                    ForeColor          = AppColors.TextSecondary,
                    SelectionBackColor = AppColors.SurfaceElevated,
                    SelectionForeColor = AppColors.TextPrimary
                }
            };

            _grid.Columns.Add(new DataGridViewTextBoxColumn
                { Name = "Name",       HeaderText = "Employee Name",  FillWeight = 24 });
            _grid.Columns.Add(new DataGridViewTextBoxColumn
                { Name = "Dept",       HeaderText = "Department",     FillWeight = 17 });
            _grid.Columns.Add(new DataGridViewTextBoxColumn
                { Name = "Finalized",  HeaderText = "Finalized",      FillWeight = 13 });
            _grid.Columns.Add(new DataGridViewTextBoxColumn
                { Name = "PdfStatus",  HeaderText = "PDF",            FillWeight = 8  });
            _grid.Columns.Add(new DataGridViewTextBoxColumn
                { Name = "LockStatus", HeaderText = "Lock",           FillWeight = 8  });
            _grid.Columns.Add(new DataGridViewTextBoxColumn
                { Name = "Path",       HeaderText = "Network Path",   FillWeight = 30 });

            // Hidden tag column stores RecordId for lookup
            _grid.Columns.Add(new DataGridViewTextBoxColumn
                { Name = "RecordId", Visible = false });

            _grid.SelectionChanged += OnGridSelectionChanged;
            _grid.CellDoubleClick  += OnGridDoubleClick;

            // Assemble — order matters: grid fills remaining space
            this.Controls.Add(_grid);
            this.Controls.Add(_actionBar);
            this.Controls.Add(topBar);
        }

        protected override void OnLayout(LayoutEventArgs e)
        {
            base.OnLayout(e);
            if (_btnRefresh == null) return;
            _btnRefresh.Left = Width - _btnRefresh.Width - Padding.Right * 2;
        }

        // ── Data ─────────────────────────────────────────────────────

        private void LoadRecords()
        {
            var index = _appSettings.LoadRecordIndex();

            // Deduplicate on load
            var seen  = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var clean = new List<RecordIndexEntry>();

            foreach (var e in index.Entries)
            {
                string key = !string.IsNullOrEmpty(e.PdfPath)
                    ? e.PdfPath.ToLowerInvariant()
                    : $"{e.EmployeeName?.ToLowerInvariant()}|{e.FinalizedAt:yyyy-MM-dd}";

                if (seen.Add(key))
                    clean.Add(e);
            }

            if (clean.Count != index.Entries.Count)
            {
                index.Entries = clean;
                _appSettings.SaveRecordIndex(index);
            }

            _entries = index.Entries;
            PopulateGrid();
        }

        private void PopulateGrid()
        {
            _grid.Rows.Clear();

            foreach (var e in _entries)
            {
                bool pdfExists = !string.IsNullOrEmpty(e.PdfPath) && File.Exists(e.PdfPath);

                // Check live lock status for this entry
                string lockStatus = "—";
                if (!string.IsNullOrEmpty(e.JsonPath))
                {
                    var foreign = LockManager.GetForeignLock(e.JsonPath);
                    if (foreign != null)
                        lockStatus = $"🔒 {foreign.DisplayName}";
                }

                int rowIdx = _grid.Rows.Add(
                    e.EmployeeName,
                    e.Department ?? string.Empty,
                    e.FinalizedAt.ToString("MM/dd/yyyy"),
                    pdfExists ? "✓" : "—",
                    lockStatus,
                    e.PdfPath ?? e.JsonPath ?? string.Empty,
                    e.RecordId
                );

                // Tint locked rows so they stand out
                if (lockStatus != "—")
                {
                    _grid.Rows[rowIdx].DefaultCellStyle.ForeColor = AppColors.StatusWarn;
                }
            }

            _lblCount.Text = _entries.Count == 1
                ? "1 record" : $"{_entries.Count} records";

            UpdateButtons(null);
        }

        // ── Event handlers ────────────────────────────────────────────

        private void OnRefreshClicked(object sender, EventArgs e)
        {
            _btnRefresh.Enabled = false;
            _btnRefresh.Text    = "Refreshing...";
            try
            {
                ExportManager.RequeryNetworkShare(_appSettings);
                LoadRecords();
                ShowStatus($"Refreshed — {_entries.Count} records found");
            }
            catch (Exception ex)
            {
                ShowStatus($"Refresh failed: {ex.Message}", error: true);
            }
            finally
            {
                _btnRefresh.Enabled = true;
                _btnRefresh.Text    = "⟳  Refresh from Network";
            }
        }

        private void OnGridSelectionChanged(object sender, EventArgs e)
        {
            UpdateButtons(SelectedEntry());
        }

        private void OnGridDoubleClick(object sender, DataGridViewCellEventArgs e)
        {
            if (e.RowIndex < 0) return;
            OpenPdf(SelectedEntry());
        }

        private void OnOpenPdfClicked(object sender, EventArgs e)
            => OpenPdf(SelectedEntry());

        private void OnOpenFolderClicked(object sender, EventArgs e)
        {
            var entry = SelectedEntry();
            if (entry == null) return;
            string path = entry.PdfPath ?? entry.JsonPath;
            if (string.IsNullOrEmpty(path)) return;
            string dir = Path.GetDirectoryName(path);
            if (Directory.Exists(dir))
                Process.Start("explorer.exe", dir);
            else
                ShowStatus("Folder not found on network share.", error: true);
        }

        private void OnResendEmailClicked(object sender, EventArgs e)
        {
            var entry = SelectedEntry();
            if (entry == null) return;

            try
            {
                OnboardingRecord record = null;
                if (!string.IsNullOrEmpty(entry.JsonPath) && File.Exists(entry.JsonPath))
                {
                    string json = File.ReadAllText(entry.JsonPath);
                    record = Newtonsoft.Json.JsonConvert.DeserializeObject<OnboardingRecord>(json);
                }

                if (record == null)
                {
                    var parts = (entry.EmployeeName ?? "").Split(',');
                    record = new OnboardingRecord
                    {
                        EmployeeLastName  = parts.Length > 0 ? parts[0].Trim() : string.Empty,
                        EmployeeFirstName = parts.Length > 1 ? parts[1].Trim() : string.Empty,
                        Department        = entry.Department,
                        ExportedAt        = entry.FinalizedAt,
                        ExportPdfPath     = entry.PdfPath
                    };
                }

                ExportManager.OpenOutlookEmail(record, entry.PdfPath);
                ShowStatus("Email client opened.");
            }
            catch (Exception ex)
            {
                ShowStatus(ex.Message, error: true);
            }
        }

        private void OnRestartClicked(object sender, EventArgs e)
        {
            var entry = SelectedEntry();
            if (entry == null) return;

            // ── Confirm with user before doing anything ───────────────
            var confirm = MessageBox.Show(
                "Restart onboarding for " + entry.EmployeeName + "?\n\n" +
                "A copy of the finalized record will be moved back to In Progress.\n" +
                "The network JSON file will be locked while you are editing it,\n" +
                "preventing other users from restarting the same record.\n\n" +
                "Continue?",
                "Restart Onboarding",
                MessageBoxButtons.OKCancel,
                MessageBoxIcon.Question);

            if (confirm != DialogResult.OK) return;

            // ── Load the source record JSON ───────────────────────────
            OnboardingRecord source = null;
            try
            {
                if (string.IsNullOrEmpty(entry.JsonPath) || !File.Exists(entry.JsonPath))
                {
                    ShowStatus("Cannot restart — JSON file not found on network share.", error: true);
                    return;
                }
                string json = File.ReadAllText(entry.JsonPath);
                source = Newtonsoft.Json.JsonConvert.DeserializeObject<OnboardingRecord>(json);
            }
            catch (Exception ex)
            {
                ShowStatus("Failed to load record: " + ex.Message, error: true);
                return;
            }

            // ── Attempt restart (includes lock acquisition) ───────────
            var draftMgr = new DraftManager(_appSettings);
            var result   = draftMgr.RestartFromRecord(source, entry.JsonPath);

            if (result.Success)
            {
                FinishRestart(result.NewDraft);
                return;
            }

            // ── Handle failure reasons ────────────────────────────────
            switch (result.Reason)
            {
                case RestartFailReason.LockedByOther:
                {
                    var lf = result.ExistingLock;
                    MessageBox.Show(
                        $"This record is currently being edited by:\n\n" +
                        $"  Name:     {lf.LockedBy ?? lf.LockedByUser ?? "Unknown"}\n" +
                        $"  Machine:  {lf.LockedByMachine ?? "Unknown"}\n" +
                        $"  Account:  {lf.LockedByUser ?? "Unknown"}\n" +
                        $"  Since:    {lf.AgeDescription}\n\n" +
                        "Please ask them to finish or discard their draft before restarting.",
                        "Record Locked",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Warning);

                    ShowStatus($"Locked by {lf.DisplayName} — cannot restart.", error: true);
                    LoadRecords(); // Refresh grid to show current lock state
                    break;
                }

                case RestartFailReason.StaleLock:
                {
                    var lf = result.ExistingLock;
                    var overrideResult = MessageBox.Show(
                        $"This record has a lock that appears to be abandoned:\n\n" +
                        $"  Name:     {lf.LockedBy ?? lf.LockedByUser ?? "Unknown"}\n" +
                        $"  Machine:  {lf.LockedByMachine ?? "Unknown"}\n" +
                        $"  Account:  {lf.LockedByUser ?? "Unknown"}\n" +
                        $"  Locked:   {lf.AgeDescription}  (over {(int)LockFile.StaleThreshold.TotalHours} hours ago)\n\n" +
                        "This lock is probably stale. Override it and continue?",
                        "Stale Lock Detected",
                        MessageBoxButtons.YesNo,
                        MessageBoxIcon.Warning,
                        MessageBoxDefaultButton.Button2);  // Default to No for safety

                    if (overrideResult == DialogResult.Yes)
                    {
                        var forced = draftMgr.ForceRestartFromRecord(source, entry.JsonPath);
                        if (forced.Success)
                            FinishRestart(forced.NewDraft);
                        else
                            ShowStatus("Restart failed after override: " + forced.ErrorMessage, error: true);
                    }
                    else
                    {
                        ShowStatus("Restart cancelled.", error: false);
                    }
                    break;
                }

                case RestartFailReason.LockError:
                {
                    // Network path issue writing the lock — warn but allow continuation
                    var proceedAnyway = MessageBox.Show(
                        $"Could not write the lock file to the network share:\n\n" +
                        $"  {result.ErrorMessage}\n\n" +
                        "This may mean the network path is unavailable or read-only.\n" +
                        "You can still restart the draft, but there is no collision protection.\n\n" +
                        "Proceed without lock protection?",
                        "Lock File Error",
                        MessageBoxButtons.YesNo,
                        MessageBoxIcon.Warning,
                        MessageBoxDefaultButton.Button2);

                    if (proceedAnyway == DialogResult.Yes)
                    {
                        // Create draft without lock (pass empty source path)
                        var unlocked = draftMgr.ForceRestartFromRecord(source, string.Empty);
                        if (unlocked.Success)
                            FinishRestart(unlocked.NewDraft);
                        else
                            ShowStatus("Restart failed: " + unlocked.ErrorMessage, error: true);
                    }
                    else
                    {
                        ShowStatus("Restart cancelled.", error: false);
                    }
                    break;
                }
            }
        }

        // ── Restart completion helper ─────────────────────────────────

        private void FinishRestart(OnboardingRecord newDraft)
        {
            var shell = FindForm() as MainShell;
            if (shell != null)
            {
                shell.RefreshNav();
                shell.NavigateTo("drafts");
            }

            ShowStatus($"Restarted — now in In Progress as new draft.");
        }

        // ── Helpers ──────────────────────────────────────────────────

        private void UpdateButtons(RecordIndexEntry entry)
        {
            bool hasEntry = entry != null;
            bool pdfOk    = hasEntry && !string.IsNullOrEmpty(entry.PdfPath);

            // Check if the selected record is locked by someone else
            bool lockedByOther = false;
            if (hasEntry && !string.IsNullOrEmpty(entry.JsonPath))
                lockedByOther = LockManager.IsLockedByOther(entry.JsonPath);

            _btnOpenPdf.Enabled     = pdfOk;
            _btnOpenFolder.Enabled  = hasEntry;
            _btnResendEmail.Enabled = hasEntry;

            // Disable Restart if locked by another user; tooltip explains why
            _btnRestart.Enabled = hasEntry && !lockedByOther;
            if (lockedByOther)
            {
                var lf = LockManager.GetForeignLock(entry.JsonPath);
                string tip = lf != null
                    ? $"Locked by {lf.DisplayName}"
                    : "Currently locked by another user";
                var tt = new ToolTip();
                tt.SetToolTip(_btnRestart, tip);
            }
        }

        private void OpenPdf(RecordIndexEntry entry)
        {
            if (entry == null) return;
            if (string.IsNullOrEmpty(entry.PdfPath) || !File.Exists(entry.PdfPath))
            {
                ShowStatus("PDF not found on network share.", error: true);
                return;
            }
            try { Process.Start(new ProcessStartInfo { FileName = entry.PdfPath, UseShellExecute = true }); }
            catch (Exception ex) { ShowStatus(ex.Message, error: true); }
        }

        private RecordIndexEntry SelectedEntry()
        {
            if (_grid.SelectedRows.Count == 0) return null;
            string id = _grid.SelectedRows[0].Cells["RecordId"].Value?.ToString();
            if (string.IsNullOrEmpty(id)) return null;
            return _entries.Find(e => e.RecordId == id);
        }

        private void ShowStatus(string msg, bool error = false)
        {
            _lblStatus.Text      = msg;
            _lblStatus.ForeColor = error ? AppColors.StatusError : AppColors.StatusSuccess;
        }
    }
}
