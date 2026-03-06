// =============================================================
// ArnotOnboarding — WizardView.cs
// Version    : 1.3.0.0
// Author     : Sam Kirsch
// Company    : Databranch
// Created    : 2026-02-22
// Modified   : 2026-02-27
// Description: 10-page wizard controller matching the Arnot Realty
//              New User IT Request Form (Steps 1-35).
//              Auto-save: debounce (750ms) on every field change
//              PLUS an immediate flush on every Back/Next navigation.
// =============================================================

using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;
using ArnotOnboarding.Managers;
using ArnotOnboarding.Models;
using ArnotOnboarding.Theme;
using ArnotOnboarding.Utilities;
using ArnotOnboarding.Views.WizardPages;

namespace ArnotOnboarding.Views
{
    public partial class WizardView : UserControl
    {
        // ── State ────────────────────────────────────────────────────
        private OnboardingRecord       _record;
        private int                    _currentPageIndex = 0;
        private readonly DraftManager  _draftManager;
        private readonly AutoSaveTimer _autoSave;

        private readonly List<WizardPageBase> _pages = new List<WizardPageBase>();

        // ── Progress bar geometry ─────────────────────────────────────
        private const int PROGRESS_HEIGHT = 60;
        private const int NAV_BAR_HEIGHT  = 56;

        // ── Constructors ─────────────────────────────────────────────
        private WizardView()
        {
            _draftManager = new DraftManager(AppSettingsManager.Instance);
            InitializeComponent();
            ThemeHelper.ApplyTheme(this);
            BuildPages();

            _autoSave = new AutoSaveTimer(
                AppSettingsManager.Instance.Settings.AutoSaveDebounceMs,
                ExecuteAutoSave);
            _autoSave.SaveFired += (s, e) => ShowSavedIndicator();
        }

        // ── Public factory methods ───────────────────────────────────

        public static WizardView StartNew()
        {
            string firstName = string.Empty, lastName = string.Empty;
            using (var dlg = new NewEmployeeDialog())
            {
                if (dlg.ShowDialog() != DialogResult.OK) return null;
                firstName = dlg.FirstName;
                lastName  = dlg.LastName;
            }
            var wv = new WizardView();
            wv._record = wv._draftManager.CreateDraft(firstName, lastName, 0);
            wv.LoadCurrentPage();
            wv.UpdateProgress();
            return wv;
        }

        public static WizardView Resume(string recordId, int lastPageIndex = 0)
        {
            var wv = new WizardView();
            wv._record = wv._draftManager.LoadDraft(recordId);
            if (wv._record == null) return null;
            wv._currentPageIndex = Math.Max(0, Math.Min(lastPageIndex, wv._pages.Count - 1));
            wv.LoadCurrentPage();
            wv.UpdateProgress();
            return wv;
        }

        // ── Build Pages ──────────────────────────────────────────────

        private void BuildPages()
        {
            _pages.AddRange(new WizardPageBase[]
            {
                new Page01_Request(),
                new Page02_UserInformation(),
                new Page03_RequestorInfo(),
                new Page04_AccountsAndCredentials(),
                new Page05_OtherAccounts(),
                new Page06_Computer(),
                new Page06b_MonitorsApps(),
                new Page07_PrintScanAccess(),
                new Page08_Email(),
                new Page09_PhoneMobile(),
                new Page10_ConfirmationNotes()
            });

            // ── Bidirectional computer name sync ───────────────────
            // Page02.PrimaryComputerName ↔ Page06.Q12 Computer Name
            if (_pages[1] is WizardPages.Page02_UserInformation p2 &&
                _pages[5] is WizardPages.Page06_Computer p6)
            {
                p2.ComputerNameChanged += (s, name) => p6.SyncComputerName(name);
                p6.ComputerNameChanged += (s, name) => p2.SyncComputerName(name);
            }

            foreach (var page in _pages)
            {
                page.DataChanged += OnPageDataChanged;
                // Do NOT use Dock=Fill — that locks the page to the host size
                // and prevents _pageHost.AutoScroll from ever activating.
                // Instead set a wide fixed width and tall minimum height.
                // The host scrolls vertically when content exceeds its height.
                page.Dock    = DockStyle.None;
                page.Width   = 800;   // Will be resized on host resize
                page.Height  = 2400;  // Generous — all pages fit within this
                page.Visible = false;
            }
        }

        // ── Navigation ───────────────────────────────────────────────

        private void btnBack_Click(object sender, EventArgs e)
        {
            if (_currentPageIndex == 0) return;
            FlushAndSave();
            _currentPageIndex--;
            LoadCurrentPage();
        }

        private void btnNext_Click(object sender, EventArgs e)
        {
            string err = _pages[_currentPageIndex].Validate();
            if (!string.IsNullOrEmpty(err))
            {
                MessageBox.Show(err, "Required Field", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            if (_currentPageIndex >= _pages.Count - 1) return;
            FlushAndSave();
            _currentPageIndex++;
            LoadCurrentPage();
        }

        private void btnSaveClose_Click(object sender, EventArgs e)
        {
            FlushAndSave();
            var shell = FindForm() as MainShell;
            if (shell != null) { shell.RefreshNav(); shell.NavigateTo("drafts"); }
        }

        private void btnFinalize_Click(object sender, EventArgs e)
        {
            // Final flush before export
            FlushAndSave();

            // Confirm intent
            var confirm = MessageBox.Show(
                $"Finalize onboarding form for {_record.FullName}?\n\n" +
                "This will:\n" +
                "  • Generate a PDF and JSON on the HR network share\n" +
                "  • Move this record to Past Records\n" +
                "  • Open Outlook to notify the Databranch support team\n\n" +
                "This action cannot be undone.",
                "Finalize & Export",
                MessageBoxButtons.OKCancel,
                MessageBoxIcon.Question);

            if (confirm != DialogResult.OK) return;

            // Disable button during export to prevent double-click
            _btnFinalize.Enabled = false;
            _btnFinalize.Text    = "Exporting...";

            try
            {
                var result = Managers.ExportManager.Finalize(
                    _record, Managers.AppSettingsManager.Instance);

                if (!result.Success)
                {
                    MessageBox.Show(
                        "Export failed:\n\n" + result.ErrorMessage,
                        "Export Error",
                        MessageBoxButtons.OK, MessageBoxIcon.Error);
                    return;
                }

                // Open Outlook email
                try
                {
                    Managers.ExportManager.OpenOutlookEmail(_record, result.PdfPath);
                }
                catch (Exception emailEx)
                {
                    MessageBox.Show(
                        "Export succeeded but could not open email client:\n\n" +
                        emailEx.Message,
                        "Email Warning",
                        MessageBoxButtons.OK, MessageBoxIcon.Warning);
                }

                // Navigate to Past Records
                var shell = FindForm() as MainShell;
                if (shell != null)
                {
                    shell.RefreshNav();
                    shell.NavigateTo("records");
                }
            }
            finally
            {
                _btnFinalize.Enabled = true;
                _btnFinalize.Text    = "Finalize & Export  ✓";
            }
        }

        // ── Load / Save ──────────────────────────────────────────────

        private void LoadCurrentPage()
        {
            var page = _pages[_currentPageIndex];
            page.LoadData(_record);

            _pageHost.Controls.Clear();

            // Size the page to match host width; use a tall fixed height so
            // _pageHost.AutoScroll activates for long pages.
            int hostW = System.Math.Max(600, _pageHost.ClientSize.Width);
            page.Width  = hostW;
            // Size page to fit its actual content so the host doesn't scroll
            // further than needed. GetPreferredContentHeight scans child control
            // bounds; if that fails, fall back to a safe maximum.
            page.Height = GetPageContentHeight(page);
            page.Left   = 0;
            page.Top    = 8;   // Physical offset from _pageHost top edge

            // Cross-page field sync — push data from earlier pages into later pages
            SyncCrossPageFields();

            _pageHost.Controls.Add(page);

            // Reset scroll to top AFTER adding (adding can shift scroll position).
            // Use SetScrollPos rather than AutoScrollPosition to avoid WinForms
            // applying a negative offset that hides the first ~20px of content.
            _pageHost.AutoScrollPosition = new System.Drawing.Point(0, 0);

            page.Visible = true;
            UpdateProgress();
            UpdateNavButtons();
        }

        private void FlushAndSave()
        {
            _autoSave.Cancel();
            _pages[_currentPageIndex].SaveData(_record);
            _draftManager.SaveDraft(_record, _currentPageIndex);
            ShowSavedIndicator();
        }

        private void ExecuteAutoSave()
        {
            _pages[_currentPageIndex].SaveData(_record);
            _draftManager.SaveDraft(_record, _currentPageIndex);
        }

        private void OnPageDataChanged(object sender, EventArgs e)
        {
            _autoSave.Bump();
            _lblSaved.Text      = "Saving...";
            _lblSaved.ForeColor = AppColors.TextDim;
        }

        private void ShowSavedIndicator()
        {
            if (_lblSaved.IsDisposed || !_lblSaved.IsHandleCreated) return;
            if (_lblSaved.InvokeRequired) { _lblSaved.Invoke(new Action(ShowSavedIndicator)); return; }
            _lblSaved.Text      = "✓ Saved";
            _lblSaved.ForeColor = AppColors.StatusSuccess;
        }

        // ── Progress & Nav Updates ────────────────────────────────────

        private void UpdateProgress()
        {
            _progressPanel.Invalidate();
        }

        private void UpdateNavButtons()
        {
            bool isLast = (_currentPageIndex == _pages.Count - 1);
            _btnBack.Enabled     = (_currentPageIndex > 0);
            _btnNext.Visible     = !isLast;
            _btnFinalize.Visible = isLast;
        }

        // ── Progress Panel Paint ─────────────────────────────────────
        // Draws: page title (left), employee name (right), step counter,
        // and a filled progress bar at the bottom of the panel.

        private void progressPanel_Paint(object sender, PaintEventArgs e)
        {
            var  g    = e.Graphics;
            int  w    = _progressPanel.Width;
            int  h    = _progressPanel.Height;
            const int pad  = 20;
            const int barH = 4;
            int  barY = h - barH - 1;   // flush to bottom of panel

            // Background — already set via BackColor, no need to fill

            // Bottom border line
            using (var pen = new Pen(AppColors.BorderDefault))
                g.DrawLine(pen, 0, h - 1, w, h - 1);

            // Progress bar track
            using (var track = new SolidBrush(AppColors.SurfaceOverlay))
                g.FillRectangle(track, pad, barY, w - pad * 2, barH);

            // Progress bar fill
            int trackW = w - pad * 2;
            int fillW  = (int)(trackW * (float)(_currentPageIndex + 1) / _pages.Count);
            using (var fill = new SolidBrush(AppColors.BrandRedSoft))
                g.FillRectangle(fill, pad, barY, fillW, barH);

            // Page title — large, left
            string title = _pages[_currentPageIndex].PageTitle;
            using (var tb = new SolidBrush(AppColors.TextPrimary))
                g.DrawString(title, AppFonts.Heading3, tb, pad, 10);

            // Step counter — small, below title
            string counter = string.Format("Page {0} of {1}", _currentPageIndex + 1, _pages.Count);
            using (var cb = new SolidBrush(AppColors.TextMuted))
                g.DrawString(counter, AppFonts.Caption, cb, pad, 34);

            // Employee name — right-aligned, top
            if (_record != null && !string.IsNullOrEmpty(_record.DisplayName)
                && _record.DisplayName != "(No Name)")
            {
                using (var nb = new SolidBrush(AppColors.TextMuted))
                {
                    SizeF sz = g.MeasureString(_record.DisplayName, AppFonts.BodySmall);
                    g.DrawString(_record.DisplayName, AppFonts.BodySmall, nb, w - pad - sz.Width, 12);
                }
            }
        }

        // ── Page height calculation ───────────────────────────────────

        /// <summary>
        /// Scans all child control bounds and returns the height needed to
        /// show all content plus bottom padding. Replaces the fixed 2400px
        /// allocation so pages don't scroll further than their content.
        /// </summary>
        private static int GetPageContentHeight(System.Windows.Forms.UserControl page)
        {
            int maxBottom = 0;
            foreach (System.Windows.Forms.Control c in page.Controls)
            {
                int b = c.Bottom + 32;   // 32px bottom padding
                if (b > maxBottom) maxBottom = b;
            }
            return System.Math.Max(400, maxBottom);  // minimum 400px
        }

        // ── Cross-page field sync ─────────────────────────────────────

        /// <summary>
        /// Pushes data from earlier pages into later pages so auto-filled
        /// fields (username, email) always reflect the current employee name.
        /// Called after each page load and after each navigation.
        /// </summary>
        private void SyncCrossPageFields()
        {
            // Save current page state into _record so data flows forward
            if (_record != null)
                _pages[_currentPageIndex].SaveData(_record);

            // Page04: sync username/email from employee name
            if (_pages.Count > 3 &&
                _pages[3] is WizardPages.Page04_AccountsAndCredentials p4)
                p4.SyncFromRecord(_record);

            // Page02 ↔ Page06: push computer name whichever page was just saved
            if (_pages.Count > 5 &&
                _pages[1] is WizardPages.Page02_UserInformation p2sync &&
                _pages[5] is WizardPages.Page06_Computer p6sync)
            {
                // Authoritative value is whichever field is non-empty, prefer record
                string cn = _record.ExistingComputerName ?? _record.PrimaryComputerName ?? string.Empty;
                if (!string.IsNullOrEmpty(cn))
                {
                    p2sync.SyncComputerName(cn);
                    p6sync.SyncComputerName(cn);
                }
            }
        }

        // ── Dispose ──────────────────────────────────────────────────

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                _autoSave?.FlushNow();
                _autoSave?.Dispose();
                if (components != null) components.Dispose();
            }
            base.Dispose(disposing);
        }
    }
}
