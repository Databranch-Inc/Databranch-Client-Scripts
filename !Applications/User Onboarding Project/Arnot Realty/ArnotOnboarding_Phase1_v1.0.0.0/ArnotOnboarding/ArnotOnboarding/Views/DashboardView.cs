// =============================================================
// ArnotOnboarding — DashboardView.cs
// Version    : 1.0.0.0
// Author     : Sam Kirsch
// Company    : Databranch
// Created    : 2026-02-22
// Modified   : 2026-02-22
// Description: Landing view shown when the app opens. Displays a
//              "Start New Onboarding" prompt and a quick-access
//              list of recent in-progress drafts. Phase 3 will
//              replace this stub with the full wizard launcher.
// =============================================================

using System;
using System.Drawing;
using System.Windows.Forms;
using ArnotOnboarding.Managers;
using ArnotOnboarding.Theme;

namespace ArnotOnboarding.Views
{
    public partial class DashboardView : UserControl
    {
        public DashboardView()
        {
            InitializeComponent();
            ThemeHelper.ApplyTheme(this);
            LoadRecentDrafts();
        }

        private void LoadRecentDrafts()
        {
            _recentLabel.Text = string.Empty;
            try
            {
                var dm = new DraftManager(AppSettingsManager.Instance);
                var drafts = dm.GetAllDrafts();
                if (drafts.Count == 0)
                {
                    _recentLabel.Text = "No in-progress onboardings. Click below to start one.";
                }
                else
                {
                    _recentLabel.Text = $"{drafts.Count} onboarding(s) in progress. " +
                                        "Use the \"In Progress\" section to resume.";
                }
            }
            catch { }
        }

        private void btnNewOnboarding_Click(object sender, EventArgs e)
        {
            // Phase 3: open wizard. For now, show message.
            MessageBox.Show(
                "The wizard will be available in Phase 3.\n\n" +
                "Foundation (Phase 1) is complete — models, managers, shell, and theme are all wired up.",
                "Coming in Phase 3",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information);
        }
    }
}
