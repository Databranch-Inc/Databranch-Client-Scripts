// =============================================================
// ArnotOnboarding — DashboardView.cs
// Version    : 1.2.0.0
// Author     : Sam Kirsch
// Company    : Databranch
// Created    : 2026-02-22
// Modified   : 2026-02-22
// Description: Landing "New Onboarding" view. Shows a start button
//              and a subtle recovery banner when in-progress drafts
//              exist. Phase 3 will wire the start button into the
//              full wizard.
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
        }

        /// <summary>
        /// Called by MainShell after the form loads. Checks for existing drafts
        /// and shows or hides the recovery banner accordingly.
        /// </summary>
        public void CheckForDrafts()
        {
            try
            {
                var dm     = new DraftManager(AppSettingsManager.Instance);
                var drafts = dm.GetAllDrafts();

                if (drafts.Count > 0)
                {
                    string noun = drafts.Count == 1 ? "onboarding" : "onboardings";
                    _bannerLabel.Text =
                        string.Format("  {0} in-progress {1} waiting — click \"In Progress\" to resume.",
                            drafts.Count, noun);
                    _recoveryBanner.Visible = true;
                }
                else
                {
                    _recoveryBanner.Visible = false;
                }
            }
            catch
            {
                _recoveryBanner.Visible = false;
            }
        }

        private void btnNewOnboarding_Click(object sender, EventArgs e)
        {
            var shell = this.FindForm() as MainShell;
            if (shell == null) return;

            var wizard = WizardView.StartNew();
            if (wizard == null) return; // User cancelled name dialog

            shell.ShowWizard(wizard);
        }

        private void btnGoToInProgress_Click(object sender, EventArgs e)
        {
            var shell = this.FindForm() as MainShell;
            if (shell != null) shell.NavigateTo("drafts");
        }
    }
}
