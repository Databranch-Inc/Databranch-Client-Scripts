namespace ArnotOnboarding.Views
{
    partial class DashboardView
    {
        private System.ComponentModel.IContainer components = null;

        private System.Windows.Forms.Label  _headerLabel;
        private System.Windows.Forms.Label  _subtitleLabel;
        private System.Windows.Forms.Label  _recentLabel;
        private System.Windows.Forms.Button _btnNewOnboarding;
        private System.Windows.Forms.Panel  _heroPanel;

        protected override void Dispose(bool disposing)
        {
            if (disposing && components != null) components.Dispose();
            base.Dispose(disposing);
        }

        private void InitializeComponent()
        {
            _heroPanel         = new System.Windows.Forms.Panel();
            _headerLabel       = new System.Windows.Forms.Label();
            _subtitleLabel     = new System.Windows.Forms.Label();
            _recentLabel       = new System.Windows.Forms.Label();
            _btnNewOnboarding  = new System.Windows.Forms.Button();

            _heroPanel.SuspendLayout();
            this.SuspendLayout();

            // Hero panel
            _heroPanel.Dock = System.Windows.Forms.DockStyle.Fill;
            _heroPanel.BackColor = Theme.AppColors.SurfaceBase;
            _heroPanel.Padding = new System.Windows.Forms.Padding(60, 80, 60, 60);
            _heroPanel.Controls.AddRange(new System.Windows.Forms.Control[]
                { _headerLabel, _subtitleLabel, _recentLabel, _btnNewOnboarding });

            // Header
            _headerLabel.AutoSize  = true;
            _headerLabel.Text      = "Start a New Onboarding";
            _headerLabel.Font      = Theme.AppFonts.Heading1;
            _headerLabel.ForeColor = Theme.AppColors.TextPrimary;
            _headerLabel.Location  = new System.Drawing.Point(60, 80);

            // Subtitle
            _subtitleLabel.AutoSize  = true;
            _subtitleLabel.Text      = "A Databranch Onboarding Form for Arnot Realty";
            _subtitleLabel.Font      = Theme.AppFonts.Body;
            _subtitleLabel.ForeColor = Theme.AppColors.TextMuted;
            _subtitleLabel.Location  = new System.Drawing.Point(60, 116);

            // Recent note
            _recentLabel.AutoSize  = false;
            _recentLabel.Size      = new System.Drawing.Size(500, 40);
            _recentLabel.Font      = Theme.AppFonts.BodySmall;
            _recentLabel.ForeColor = Theme.AppColors.TextMuted;
            _recentLabel.Location  = new System.Drawing.Point(60, 200);

            // Start button
            _btnNewOnboarding.Text     = "＋  New Onboarding Request";
            _btnNewOnboarding.Size     = new System.Drawing.Size(240, 44);
            _btnNewOnboarding.Location = new System.Drawing.Point(60, 256);
            _btnNewOnboarding.Click   += new System.EventHandler(this.btnNewOnboarding_Click);
            Theme.ThemeHelper.ApplyButtonStyle(_btnNewOnboarding, Theme.ThemeHelper.ButtonStyle.Primary);

            this.Controls.Add(_heroPanel);
            this.Dock = System.Windows.Forms.DockStyle.Fill;

            _heroPanel.ResumeLayout(false);
            this.ResumeLayout(false);
        }
    }
}
