// =============================================================
// ArnotOnboarding — DashboardView.Designer.cs
// Version    : 1.1.0.0
// =============================================================

namespace ArnotOnboarding.Views
{
    partial class DashboardView
    {
        private System.ComponentModel.IContainer components = null;

        // ── Controls ─────────────────────────────────────────────────
        private System.Windows.Forms.Panel  _recoveryBanner;
        private System.Windows.Forms.Label  _bannerLabel;
        private System.Windows.Forms.Button _btnGoToInProgress;
        private System.Windows.Forms.Panel  _heroPanel;
        private System.Windows.Forms.Label  _eyebrowLabel;
        private System.Windows.Forms.Label  _headerLabel;
        private System.Windows.Forms.Label  _subtitleLabel;
        private System.Windows.Forms.Button _btnNewOnboarding;

        protected override void Dispose(bool disposing)
        {
            if (disposing && components != null) components.Dispose();
            base.Dispose(disposing);
        }

        private void InitializeComponent()
        {
            _recoveryBanner    = new System.Windows.Forms.Panel();
            _bannerLabel       = new System.Windows.Forms.Label();
            _btnGoToInProgress = new System.Windows.Forms.Button();
            _heroPanel         = new System.Windows.Forms.Panel();
            _eyebrowLabel      = new System.Windows.Forms.Label();
            _headerLabel       = new System.Windows.Forms.Label();
            _subtitleLabel     = new System.Windows.Forms.Label();
            _btnNewOnboarding  = new System.Windows.Forms.Button();

            _recoveryBanner.SuspendLayout();
            _heroPanel.SuspendLayout();
            this.SuspendLayout();

            // ── Recovery Banner (top, hidden by default) ──────────────
            _recoveryBanner.Dock      = System.Windows.Forms.DockStyle.Top;
            _recoveryBanner.Height    = 42;
            _recoveryBanner.BackColor = Theme.AppColors.StatusInfoBg;
            _recoveryBanner.Visible   = false;

            // Blue left accent
            _recoveryBanner.Paint += (s, pe) => {
                using (var pen = new System.Drawing.SolidBrush(Theme.AppColors.BrandBlue))
                    pe.Graphics.FillRectangle(pen, 0, 0, 3, _recoveryBanner.Height);
                using (var border = new System.Drawing.Pen(Theme.AppColors.StatusInfoBd))
                    pe.Graphics.DrawLine(border, 0, _recoveryBanner.Height - 1,
                        _recoveryBanner.Width, _recoveryBanner.Height - 1);
            };

            _bannerLabel.AutoSize  = false;
            _bannerLabel.Size      = new System.Drawing.Size(560, 42);
            _bannerLabel.Location  = new System.Drawing.Point(12, 0);
            _bannerLabel.Font      = Theme.AppFonts.Body;
            _bannerLabel.ForeColor = Theme.AppColors.StatusInfo;
            _bannerLabel.TextAlign = System.Drawing.ContentAlignment.MiddleLeft;
            _bannerLabel.Text      = string.Empty;

            _btnGoToInProgress.Text     = "View In Progress →";
            _btnGoToInProgress.Size     = new System.Drawing.Size(160, 28);
            _btnGoToInProgress.Location = new System.Drawing.Point(584, 7);
            _btnGoToInProgress.Click   += new System.EventHandler(this.btnGoToInProgress_Click);
            Theme.ThemeHelper.ApplyButtonStyle(_btnGoToInProgress, Theme.ThemeHelper.ButtonStyle.Secondary);

            _recoveryBanner.Controls.Add(_bannerLabel);
            _recoveryBanner.Controls.Add(_btnGoToInProgress);

            // ── Hero Panel (main content area) ────────────────────────
            _heroPanel.Dock      = System.Windows.Forms.DockStyle.Fill;
            _heroPanel.BackColor = Theme.AppColors.SurfaceBase;

            // Eyebrow
            _eyebrowLabel.Text      = "DATABRANCH";
            _eyebrowLabel.Font      = Theme.AppFonts.EyebrowLabel;
            _eyebrowLabel.ForeColor = Theme.AppColors.BrandRedSoft;
            _eyebrowLabel.AutoSize  = true;
            _eyebrowLabel.Location  = new System.Drawing.Point(56, 72);

            // Main header
            _headerLabel.Text      = "New Onboarding Request";
            _headerLabel.Font      = Theme.AppFonts.Heading1;
            _headerLabel.ForeColor = Theme.AppColors.TextPrimary;
            _headerLabel.AutoSize  = true;
            _headerLabel.Location  = new System.Drawing.Point(56, 96);

            // Subtitle
            _subtitleLabel.Text      = "A Databranch Onboarding Form for Arnot Realty";
            _subtitleLabel.Font      = Theme.AppFonts.Body;
            _subtitleLabel.ForeColor = Theme.AppColors.TextMuted;
            _subtitleLabel.AutoSize  = true;
            _subtitleLabel.Location  = new System.Drawing.Point(56, 132);

            // Divider line (painted)
            var divider = new System.Windows.Forms.Panel();
            divider.Location  = new System.Drawing.Point(56, 166);
            divider.Size      = new System.Drawing.Size(400, 1);
            divider.BackColor = Theme.AppColors.BorderSubtle;

            // Start button
            _btnNewOnboarding.Text     = "＋  Start New Onboarding";
            _btnNewOnboarding.Size     = new System.Drawing.Size(224, 44);
            _btnNewOnboarding.Location = new System.Drawing.Point(56, 190);
            _btnNewOnboarding.Click   += new System.EventHandler(this.btnNewOnboarding_Click);
            Theme.ThemeHelper.ApplyButtonStyle(_btnNewOnboarding, Theme.ThemeHelper.ButtonStyle.Primary);

            // Helper note below button
            var noteLabel = new System.Windows.Forms.Label();
            noteLabel.Text      = "Saves automatically as you fill in each page.";
            noteLabel.Font      = Theme.AppFonts.Caption;
            noteLabel.ForeColor = Theme.AppColors.TextDim;
            noteLabel.AutoSize  = true;
            noteLabel.Location  = new System.Drawing.Point(56, 244);

            _heroPanel.Controls.AddRange(new System.Windows.Forms.Control[]
            {
                _eyebrowLabel, _headerLabel, _subtitleLabel,
                divider, _btnNewOnboarding, noteLabel
            });

            // ── Compose ───────────────────────────────────────────────
            this.Controls.Add(_heroPanel);
            this.Controls.Add(_recoveryBanner);

            this.Dock = System.Windows.Forms.DockStyle.Fill;

            _recoveryBanner.ResumeLayout(false);
            _heroPanel.ResumeLayout(false);
            this.ResumeLayout(false);
        }
    }
}
