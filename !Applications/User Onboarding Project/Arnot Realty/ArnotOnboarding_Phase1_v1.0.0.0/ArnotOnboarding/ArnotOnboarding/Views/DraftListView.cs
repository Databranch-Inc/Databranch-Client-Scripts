// =============================================================
// ArnotOnboarding — DraftListView.cs
// Version    : 1.2.0.0
// Author     : Sam Kirsch
// Company    : Databranch
// Created    : 2026-02-22
// Modified   : 2026-02-22
// Description: "In Progress" view. Displays all locally saved draft
//              onboarding records with Resume, Delete, Export and
//              Import actions. Drafts are stored in %AppData% and
//              survive app restarts and crashes.
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
        private readonly DraftManager     _draftManager;
        private List<DraftIndexEntry>     _drafts;
        private DraftIndexEntry           _selectedDraft;

        public DraftListView()
        {
            _draftManager = new DraftManager(AppSettingsManager.Instance);
            InitializeComponent();
            ThemeHelper.ApplyTheme(this);
            ApplyCustomStyling();
            LoadDrafts();
        }

        // ── Data Loading ─────────────────────────────────────────────

        public void LoadDrafts()
        {
            _drafts        = _draftManager.GetAllDrafts();
            _selectedDraft = null;
            _listView.Items.Clear();

            if (_drafts.Count == 0)
            {
                _emptyPanel.Visible  = true;
                _listView.Visible    = false;
                _detailPanel.Visible = false;
                UpdateButtonStates();
                return;
            }

            _emptyPanel.Visible = false;
            _listView.Visible   = true;

            foreach (var draft in _drafts)
            {
                var item = new ListViewItem(draft.EmployeeName ?? "(No Name)");
                item.SubItems.Add(draft.CreatedAt.ToString("MMM d, yyyy"));
                item.SubItems.Add(draft.LastModified.ToString("MMM d, yyyy  h:mm tt"));
                item.Tag = draft;
                _listView.Items.Add(item);
            }

            UpdateButtonStates();
        }

        // ── Selection ─────────────────────────────────────────────────

        private void listView_SelectedIndexChanged(object sender, EventArgs e)
        {
            if (_listView.SelectedItems.Count == 0)
            {
                _selectedDraft       = null;
                _detailPanel.Visible = false;
            }
            else
            {
                _selectedDraft = (DraftIndexEntry)_listView.SelectedItems[0].Tag;
                ShowDetailPanel(_selectedDraft);
            }
            UpdateButtonStates();
        }

        private void listView_DoubleClick(object sender, EventArgs e)
        {
            if (_selectedDraft != null) ResumeSelectedDraft();
        }

        private void ShowDetailPanel(DraftIndexEntry draft)
        {
            _detailName.Text     = draft.EmployeeName ?? "(No Name)";
            _detailStarted.Text  = "Started: "       + draft.CreatedAt.ToString("dddd, MMMM d, yyyy");
            _detailModified.Text = "Last modified: " + draft.LastModified.ToString("MMM d, yyyy  h:mm tt");
            _detailPage.Text     = string.Format("Last page: {0} of 13", draft.LastPageIndex + 1);
            _detailPanel.Visible = true;
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
            var result = MessageBox.Show(
                string.Format("Permanently delete the in-progress onboarding for:\n\n  {0}\n\nThis cannot be undone.", name),
                "Delete Draft",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Warning,
                MessageBoxDefaultButton.Button2);

            if (result != DialogResult.Yes) return;

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
                    MessageBox.Show(
                        "Draft exported successfully:\n\n" + zipPath +
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
                dialog.Title            = "Import Draft — Select Zip File";
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

                    foreach (ListViewItem item in _listView.Items)
                    {
                        var entry = (DraftIndexEntry)item.Tag;
                        if (entry.RecordId == record.RecordId)
                        {
                            item.Selected = true;
                            item.EnsureVisible();
                            break;
                        }
                    }

                    MessageBox.Show(
                        string.Format("Draft imported successfully for:\n\n  {0}\n\nIt now appears in your In Progress list.", record.DisplayName),
                        "Import Successful", MessageBoxButtons.OK, MessageBoxIcon.Information);
                }
                catch (Exception ex)
                {
                    MessageBox.Show(
                        "Import failed:\n\n" + ex.Message + "\n\nMake sure this is a valid Arnot Onboarding draft zip file.",
                        "Import Failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
        }

        // ── UI Helpers ────────────────────────────────────────────────

        private void UpdateButtonStates()
        {
            bool has = (_selectedDraft != null);
            _btnResume.Enabled = has;
            _btnDelete.Enabled = has;
            _btnExport.Enabled = has;
        }

        private void RefreshNavBadge()
        {
            var shell = this.FindForm() as MainShell;
            if (shell != null) shell.RefreshNav();
        }

        // ── ListView Owner-Draw (dark theme) ──────────────────────────

        private void ApplyCustomStyling()
        {
            _listView.OwnerDraw          = true;
            _listView.DrawColumnHeader  += listView_DrawColumnHeader;
            _listView.DrawItem          += listView_DrawItem;
            _listView.DrawSubItem       += listView_DrawSubItem;
        }

        private void listView_DrawColumnHeader(object sender, DrawListViewColumnHeaderEventArgs e)
        {
            using (var bg = new SolidBrush(AppColors.SurfaceRaised))
                e.Graphics.FillRectangle(bg, e.Bounds);

            using (var border = new Pen(AppColors.BorderDefault))
                e.Graphics.DrawLine(border,
                    e.Bounds.Left, e.Bounds.Bottom - 1,
                    e.Bounds.Right, e.Bounds.Bottom - 1);

            var fmt = new StringFormat { Alignment = StringAlignment.Near, LineAlignment = StringAlignment.Center };
            var textRect = new Rectangle(e.Bounds.X + 8, e.Bounds.Y, e.Bounds.Width - 8, e.Bounds.Height);
            using (var textBrush = new SolidBrush(AppColors.TextMuted))
                e.Graphics.DrawString(e.Header.Text, AppFonts.SectionLabel, textBrush, textRect, fmt);
        }

        private void listView_DrawItem(object sender, DrawListViewItemEventArgs e)
        {
            Color bg;
            if (e.Item.Selected)
                bg = AppColors.SurfaceOverlay;
            else if (e.ItemIndex % 2 == 0)
                bg = AppColors.SurfaceCard;
            else
                bg = AppColors.SurfaceRaised;

            using (var bgBrush = new SolidBrush(bg))
                e.Graphics.FillRectangle(bgBrush, e.Bounds);

            if (e.Item.Selected)
            {
                using (var accent = new SolidBrush(AppColors.BrandRedSoft))
                    e.Graphics.FillRectangle(accent, e.Bounds.X, e.Bounds.Y, 3, e.Bounds.Height);
            }

            e.DrawFocusRectangle();
        }

        private void listView_DrawSubItem(object sender, DrawListViewSubItemEventArgs e)
        {
            bool  isSelected = e.Item.Selected;
            Color fg = e.ColumnIndex == 0
                ? (isSelected ? AppColors.TextPrimary : AppColors.TextSecondary)
                : AppColors.TextMuted;
            Font  f  = e.ColumnIndex == 0 ? AppFonts.Body : AppFonts.BodySmall;

            var fmt = new StringFormat
            {
                Alignment     = StringAlignment.Near,
                LineAlignment = StringAlignment.Center,
                Trimming      = StringTrimming.EllipsisCharacter
            };

            var textRect = new Rectangle(
                e.Bounds.X + (e.ColumnIndex == 0 ? 10 : 6),
                e.Bounds.Y, e.Bounds.Width - 12, e.Bounds.Height);

            using (var textBrush = new SolidBrush(fg))
                e.Graphics.DrawString(e.SubItem.Text, f, textBrush, textRect, fmt);

            using (var divPen = new Pen(AppColors.BorderSubtle))
                e.Graphics.DrawLine(divPen,
                    e.Bounds.Left, e.Bounds.Bottom - 1,
                    e.Bounds.Right, e.Bounds.Bottom - 1);
        }
    }
}
