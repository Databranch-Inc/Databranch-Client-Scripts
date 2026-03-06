// =============================================================
// ArnotOnboarding — DraftListView.cs
// Version    : 1.5.8.0
// Author     : Sam Kirsch
// Company    : Databranch
// Created    : 2026-02-22
// Modified   : 2026-02-27
// Description: "In Progress" view. Uses DataGridView instead of ListView
//              for completely stable rendering — no OwnerDraw partial-repaint
//              quirks, no WM_ERASEBKGND fights, no hover artifacts.
// =============================================================

using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;
using ArnotOnboarding.Managers;
using ArnotOnboarding.Models;
using ArnotOnboarding.Theme;

namespace ArnotOnboarding.Views
{
    public partial class DraftListView : UserControl
    {
        private readonly DraftManager _draftManager;
        private List<DraftIndexEntry> _drafts;
        private DraftIndexEntry       _selectedDraft;

        public DraftListView()
        {
            _draftManager = new DraftManager(AppSettingsManager.Instance);
            InitializeComponent();
            ThemeHelper.ApplyTheme(this);
            ConfigureGrid();
            LoadDrafts();
        }

        // ── Grid Setup ────────────────────────────────────────────────

        private void ConfigureGrid()
        {
            _grid.CellClick           += grid_CellClick;
            _grid.CellDoubleClick     += grid_CellDoubleClick;
            _grid.SelectionChanged    += grid_SelectionChanged;
            _grid.Resize              += (s, e) => ResizeColumns();
        }

        private void ResizeColumns()
        {
            int w = _grid.ClientSize.Width;
            if (w < 100) return;
            _colName.Width     = (int)(w * 0.45);
            _colStarted.Width  = (int)(w * 0.22);
            _colModified.Width = w - _colName.Width - _colStarted.Width;
        }

        // ── Data Loading ─────────────────────────────────────────────

        public void LoadDrafts()
        {
            _drafts        = _draftManager.GetAllDrafts();
            _selectedDraft = null;
            ShowDetailPanel(null);

            _grid.Rows.Clear();

            if (_drafts.Count == 0)
            {
                _emptyPanel.BringToFront();
                UpdateButtonStates();
                return;
            }

            _emptyPanel.SendToBack();

            foreach (var draft in _drafts)
            {
                int idx = _grid.Rows.Add(
                    draft.EmployeeName ?? "(No Name)",
                    draft.CreatedAt.ToString("MMM d, yyyy"),
                    draft.LastModified.ToString("MMM d, yyyy  h:mm tt")
                );
                _grid.Rows[idx].Tag = draft;
            }

            ResizeColumns();
            UpdateButtonStates();
        }

        // ── Selection ─────────────────────────────────────────────────

        private void grid_CellClick(object sender, DataGridViewCellEventArgs e)
        {
            if (e.RowIndex < 0) return; // header click
            _selectedDraft = (DraftIndexEntry)_grid.Rows[e.RowIndex].Tag;
            ShowDetailPanel(_selectedDraft);
            UpdateButtonStates();
        }

        private void grid_SelectionChanged(object sender, EventArgs e)
        {
            if (_grid.SelectedRows.Count == 0)
            {
                _selectedDraft = null;
                ShowDetailPanel(null);
            }
            else
            {
                _selectedDraft = (DraftIndexEntry)_grid.SelectedRows[0].Tag;
                ShowDetailPanel(_selectedDraft);
            }
            UpdateButtonStates();
        }

        private void grid_CellDoubleClick(object sender, DataGridViewCellEventArgs e)
        {
            if (e.RowIndex >= 0 && _selectedDraft != null)
                ResumeSelectedDraft();
        }

        private void ShowDetailPanel(DraftIndexEntry draft)
        {
            if (draft == null)
            {
                _detailEmpty.Visible    = true;
                _detailName.Visible     = false;
                _detailStarted.Visible  = false;
                _detailModified.Visible = false;
                _detailPage.Visible     = false;
            }
            else
            {
                _detailEmpty.Visible    = false;
                _detailName.Text        = draft.EmployeeName ?? "(No Name)";
                _detailStarted.Text     = "Started: "       + draft.CreatedAt.ToString("dddd, MMMM d, yyyy");
                _detailModified.Text    = "Last modified: " + draft.LastModified.ToString("MMM d, yyyy  h:mm tt");
                _detailPage.Text        = string.Format("Last page: {0} of 11", draft.LastPageIndex + 1);
                _detailName.Visible     = true;
                _detailStarted.Visible  = true;
                _detailModified.Visible = true;
                _detailPage.Visible     = true;
            }
        }

        // ── Button Handlers ───────────────────────────────────────────

        private void btnResume_Click(object sender, EventArgs e)  => ResumeSelectedDraft();
        private void btnDelete_Click(object sender, EventArgs e)  => DeleteSelectedDraft();
        private void btnExport_Click(object sender, EventArgs e)  => ExportSelectedDraft();
        private void btnImport_Click(object sender, EventArgs e)  => ImportDraft();
        private void btnRefresh_Click(object sender, EventArgs e) => LoadDrafts();

        private void ResumeSelectedDraft()
        {
            if (_selectedDraft == null) return;
            var shell = this.FindForm() as MainShell;
            if (shell == null) return;

            var wizard = WizardView.Resume(_selectedDraft.RecordId, _selectedDraft.LastPageIndex);
            if (wizard == null)
            {
                MessageBox.Show(
                    "Could not load this draft. The file may have been moved or deleted.\n\n" +
                    "It will be removed from the list.",
                    "Draft Not Found", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                _draftManager.DeleteDraft(_selectedDraft.RecordId);
                LoadDrafts();
                RefreshNavBadge();
                return;
            }
            shell.ShowWizard(wizard);
        }

        private void DeleteSelectedDraft()
        {
            if (_selectedDraft == null) return;
            string name = _selectedDraft.EmployeeName ?? "this draft";
            if (MessageBox.Show(
                    string.Format("Permanently delete the in-progress onboarding for:\n\n  {0}\n\nThis cannot be undone.", name),
                    "Delete Draft", MessageBoxButtons.YesNo,
                    MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2)
                != DialogResult.Yes) return;

            try
            {
                _draftManager.DeleteDraft(_selectedDraft.RecordId);
                LoadDrafts();
                RefreshNavBadge();
            }
            catch (Exception ex)
            {
                MessageBox.Show("Failed to delete draft:\n\n" + ex.Message,
                    "Delete Failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void ExportSelectedDraft()
        {
            if (_selectedDraft == null) return;
            using (var dialog = new FolderBrowserDialog())
            {
                dialog.Description  = "Choose where to save the exported draft zip:";
                dialog.SelectedPath = AppSettingsManager.Instance.Settings.LastDraftExportDirectory;
                if (dialog.ShowDialog() != DialogResult.OK) return;

                string dir = dialog.SelectedPath;
                AppSettingsManager.Instance.Settings.LastDraftExportDirectory = dir;
                AppSettingsManager.Instance.SaveSettings();

                try
                {
                    string zipPath = _draftManager.ExportDraftAsZip(_selectedDraft.RecordId, dir);
                    MessageBox.Show("Draft exported successfully:\n\n" + zipPath +
                        "\n\nThis file can be imported on another machine using the Import button.",
                        "Export Successful", MessageBoxButtons.OK, MessageBoxIcon.Information);
                }
                catch (Exception ex)
                {
                    MessageBox.Show("Export failed:\n\n" + ex.Message,
                        "Export Failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
        }

        private void ImportDraft()
        {
            using (var dialog = new OpenFileDialog())
            {
                dialog.Title            = "Import Draft \u2014 Select Zip File";
                dialog.Filter           = "Onboarding Draft (*.zip)|*.zip|All Files (*.*)|*.*";
                dialog.InitialDirectory = AppSettingsManager.Instance.Settings.LastDraftImportDirectory;
                if (dialog.ShowDialog() != DialogResult.OK) return;

                string zipPath = dialog.FileName;
                AppSettingsManager.Instance.Settings.LastDraftImportDirectory =
                    System.IO.Path.GetDirectoryName(zipPath);
                AppSettingsManager.Instance.SaveSettings();

                try
                {
                    var record = _draftManager.ImportDraftFromZip(zipPath);
                    LoadDrafts();
                    RefreshNavBadge();

                    // Select the newly imported row
                    foreach (DataGridViewRow row in _grid.Rows)
                    {
                        var entry = (DraftIndexEntry)row.Tag;
                        if (entry.RecordId == record.RecordId)
                        {
                            row.Selected = true;
                            _grid.FirstDisplayedScrollingRowIndex = row.Index;
                            break;
                        }
                    }

                    MessageBox.Show(
                        string.Format("Draft imported successfully for:\n\n  {0}\n\nIt now appears in your In Progress list.", record.DisplayName),
                        "Import Successful", MessageBoxButtons.OK, MessageBoxIcon.Information);
                }
                catch (Exception ex)
                {
                    MessageBox.Show("Import failed:\n\n" + ex.Message +
                        "\n\nMake sure this is a valid Arnot Onboarding draft zip file.",
                        "Import Failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
        }

        // ── UI Helpers ────────────────────────────────────────────────

        private void UpdateButtonStates()
        {
            bool has        = (_selectedDraft != null);
            _btnResume.Enabled  = has;
            _btnDelete.Enabled  = has;
            _btnExport.Enabled  = has;
            _btnImport.Enabled  = true;
            _btnRefresh.Enabled = true;
        }

        private void RefreshNavBadge()
        {
            var shell = this.FindForm() as MainShell;
            shell?.RefreshNav();
        }
    }
}
