// =============================================================
// ArnotOnboarding — WizardView.cs
// Version    : 1.0.0.0
// Author     : Sam Kirsch
// Company    : Databranch
// Created    : 2026-02-22
// Modified   : 2026-02-22
// Description: Multi-page wizard controller. Hosts all 13 wizard
//              page UserControls, manages navigation, auto-save,
//              progress bar rendering, and draft lifecycle.
//
//              Can be opened two ways:
//                WizardView.StartNew()  — creates a fresh draft
//                WizardView.Resume(id)  — loads an existing draft
//
//              Auto-save:
//                - Debounce (750ms) fires on every field change
//                - Flush fires immediately on every Back/Next
//                - Both write the OnboardingRecord to disk via DraftManager
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
        private OnboardingRecord         _record;
        private int                      _currentPageIndex = 0;
        private readonly DraftManager    _draftManager;
        private readonly AutoSaveTimer   _autoSave;

        // ── Page definitions ─────────────────────────────────────────
        private readonly List<WizardPageBase> _pages = new List<WizardPageBase>();

        // ── Progress bar geometry ─────────────────────────────────────
        private const int PROGRESS_HEIGHT = 56;
        private const int NAV_BAR_HEIGHT  = 56;

        // ── Constructor helpers ──────────────────────────────────────
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

        /// <summary>
        /// Creates a new WizardView for a brand-new onboarding.
        /// Shows the employee name dialog first; returns null if user cancels.
        /// </summary>
        public static WizardView StartNew()
        {
            // Lightweight name-entry dialog before creating the draft
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

        /// <summary>
        /// Creates a new WizardView resuming an existing draft by record ID.
        /// Returns null if the draft file cannot be found.
        /// </summary>
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

        // ── Page Setup ───────────────────────────────────────────────

        private void BuildPages()
        {
            _pages.AddRange(new WizardPageBase[]
            {
                new Page01_EmployeeName(),
                new Page02_Scheduling(),
                new Page03_UserInformation(),
                new Page04_RequestorInfo(),
                new Page05_AccountSetup(),
                new Page06_EmailSetup(),
                new Page07_Applications(),
                new Page08_ComputerSetup(),
                new Page09_RemoteAccess(),
                new Page10_SoftwareAccess(),
                new Page11_AdditionalAccess(),
                new Page12_PhoneMobile(),
                new Page13_MiscNotes()
            });

            // Subscribe to DataChanged on all pages
            foreach (var page in _pages)
            {
                page.DataChanged += OnPageDataChanged;
                page.Dock         = DockStyle.Fill;
                page.Visible      = false;
            }
        }

        // ── Navigation ───────────────────────────────────────────────

        private void btnBack_Click(object sender, EventArgs e)
        {
            if (_currentPageIndex == 0) return;
            FlushAndSave();
            _currentPageIndex--;
            LoadCurrentPage();
            UpdateProgress();
            UpdateNavButtons();
        }

        private void btnNext_Click(object sender, EventArgs e)
        {
            // Validate before advancing
            string error = _pages[_currentPageIndex].Validate();
            if (!string.IsNullOrEmpty(error))
            {
                MessageBox.Show(error, "Required Field", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            // If this is the last page, use Finalize button instead
            if (_currentPageIndex >= _pages.Count - 1) return;

            FlushAndSave();
            _currentPageIndex++;
            LoadCurrentPage();
            UpdateProgress();
            UpdateNavButtons();
        }

        private void btnSaveClose_Click(object sender, EventArgs e)
        {
            FlushAndSave();
            var shell = FindForm() as MainShell;
            if (shell != null)
            {
                shell.RefreshNav();
                shell.NavigateTo("drafts");
            }
        }

        private void btnFinalize_Click(object sender, EventArgs e)
        {
            FlushAndSave();
            // Phase 4: trigger PDF export flow here.
            MessageBox.Show(
                "Export to PDF and network share will be wired up in Phase 4.\n\n" +
                "Your draft has been saved and is ready for export.",
                "Phase 4 — Export Coming Soon",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information);
        }

        // ── Load/Save Helpers ────────────────────────────────────────

        private void LoadCurrentPage()
        {
            var page = _pages[_currentPageIndex];

            // Load data into the page
            page.LoadData(_record);

            // Sync cross-page derived fields
            SyncCrossPageFields();

            // Swap visible page
            _pageHost.Controls.Clear();
            _pageHost.Controls.Add(page);
            page.Visible = true;
            page.BringToFront();

            // Update Save & Close / Finalize / Next button visibility
            UpdateNavButtons();
        }

        /// <summary>
        /// Handles fields that must stay synchronized across pages.
        /// Currently: email address (page 3 -> page 6).
        /// </summary>
        private void SyncCrossPageFields()
        {
            // If page 3 has been filled in, push email to page 6
            if (_record != null && !string.IsNullOrEmpty(_record.EmailAddress))
            {
                var p6 = _pages[5] as Page06_EmailSetup;
                if (p6 != null) p6.SyncEmail(_record.EmailAddress);

                // Also push username suggestion to page 5
                var p5 = _pages[4] as Page05_AccountSetup;
                if (p5 != null) p5.SuggestUsername(_record.EmployeeFirstName, _record.EmployeeLastName);
            }
        }

        /// <summary>
        /// Immediately saves the current page data to the record and writes
        /// the draft to disk. Called on every navigation event (belt + suspenders).
        /// </summary>
        private void FlushAndSave()
        {
            _autoSave.Cancel(); // Stop any pending debounce
            _pages[_currentPageIndex].SaveData(_record);
            _draftManager.SaveDraft(_record, _currentPageIndex);
            ShowSavedIndicator();
        }

        /// <summary>
        /// Auto-save callback invoked by the AutoSaveTimer debounce.
        /// Saves the current page data without blocking the UI.
        /// </summary>
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
            if (_lblSaved.InvokeRequired)
            {
                _lblSaved.Invoke(new Action(ShowSavedIndicator));
                return;
            }
            _lblSaved.Text      = "✓ Saved";
            _lblSaved.ForeColor = AppColors.StatusSuccess;
        }

        // ── Progress Bar & Nav Button Updates ────────────────────────

        private void UpdateProgress()
        {
            _progressPanel.Invalidate(); // Triggers the paint event
        }

        private void UpdateNavButtons()
        {
            bool isFirst = (_currentPageIndex == 0);
            bool isLast  = (_currentPageIndex == _pages.Count - 1);

            _btnBack.Enabled    = !isFirst;
            _btnNext.Visible    = !isLast;
            _btnFinalize.Visible = isLast;
        }

        // ── Progress Panel Paint ─────────────────────────────────────

        private void progressPanel_Paint(object sender, PaintEventArgs e)
        {
            var g    = e.Graphics;
            int w    = _progressPanel.Width;
            int h    = _progressPanel.Height;
            int pad  = 24;
            int barH = 4;
            int barY = h - barH - 16;

            // Background
            using (var bg = new SolidBrush(AppColors.SurfaceRaised))
                g.FillRectangle(bg, 0, 0, w, h);

            // Bottom border
            using (var border = new Pen(AppColors.BorderDefault))
                g.DrawLine(border, 0, h - 1, w, h - 1);

            // Progress bar track
            int trackW = w - pad * 2;
            using (var track = new SolidBrush(AppColors.SurfaceOverlay))
                g.FillRectangle(track, pad, barY, trackW, barH);

            // Progress bar fill
            float progress = (float)(_currentPageIndex + 1) / _pages.Count;
            int fillW = (int)(trackW * progress);
            using (var fill = new SolidBrush(AppColors.BrandRedSoft))
                g.FillRectangle(fill, pad, barY, fillW, barH);

            // Step counter (right-aligned above bar)
            string counter = string.Format("Step {0} of {1}", _currentPageIndex + 1, _pages.Count);
            using (var counterBrush = new SolidBrush(AppColors.TextMuted))
            {
                SizeF sz = g.MeasureString(counter, AppFonts.Caption);
                g.DrawString(counter, AppFonts.Caption, counterBrush, w - pad - sz.Width, barY - sz.Height - 4);
            }

            // Page title (left, large)
            string title = _pages[_currentPageIndex].PageTitle;
            using (var titleBrush = new SolidBrush(AppColors.TextPrimary))
                g.DrawString(title, AppFonts.Heading2, titleBrush, pad, 12);

            // Employee name (right, muted)
            if (_record != null && !string.IsNullOrEmpty(_record.FullName))
            {
                using (var nameBrush = new SolidBrush(AppColors.TextMuted))
                {
                    SizeF sz = g.MeasureString(_record.FullName, AppFonts.BodySmall);
                    g.DrawString(_record.FullName, AppFonts.BodySmall, nameBrush, w - pad - sz.Width, 16);
                }
            }
        }

        // ── Form Closing ─────────────────────────────────────────────

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                _autoSave?.FlushNow(); // Save anything pending before destroying
                _autoSave?.Dispose();
            }
            base.Dispose(disposing);
        }
    }
}
