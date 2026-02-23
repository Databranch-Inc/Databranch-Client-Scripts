// =============================================================
// ArnotOnboarding — WizardView.Designer.cs  v1.0.0.0
// =============================================================
namespace ArnotOnboarding.Views
{
    partial class WizardView
    {
        private System.ComponentModel.IContainer components = null;

        private System.Windows.Forms.Panel  _progressPanel;
        private System.Windows.Forms.Panel  _pageHost;
        private System.Windows.Forms.Panel  _navBar;
        private System.Windows.Forms.Button _btnBack;
        private System.Windows.Forms.Button _btnNext;
        private System.Windows.Forms.Button _btnFinalize;
        private System.Windows.Forms.Button _btnSaveClose;
        private System.Windows.Forms.Label  _lblSaved;

        protected override void Dispose(bool disposing)
        {
            if (disposing && components != null) components.Dispose();
            base.Dispose(disposing);
        }

        private void InitializeComponent()
        {
            _progressPanel = new System.Windows.Forms.Panel();
            _pageHost      = new System.Windows.Forms.Panel();
            _navBar        = new System.Windows.Forms.Panel();
            _btnBack       = new System.Windows.Forms.Button();
            _btnNext       = new System.Windows.Forms.Button();
            _btnFinalize   = new System.Windows.Forms.Button();
            _btnSaveClose  = new System.Windows.Forms.Button();
            _lblSaved      = new System.Windows.Forms.Label();

            this.SuspendLayout();

            // ── Progress Panel (top) ──────────────────────────────────
            _progressPanel.Dock    = System.Windows.Forms.DockStyle.Top;
            _progressPanel.Height  = PROGRESS_HEIGHT;
            _progressPanel.Paint  += new System.Windows.Forms.PaintEventHandler(progressPanel_Paint);

            // ── Nav Bar (bottom) ──────────────────────────────────────
            _navBar.Dock      = System.Windows.Forms.DockStyle.Bottom;
            _navBar.Height    = NAV_BAR_HEIGHT;
            _navBar.BackColor = Theme.AppColors.SurfaceRaised;

            // Bottom nav bar top border painted
            _navBar.Paint += (s, pe) => {
                using (var pen = new System.Drawing.Pen(Theme.AppColors.BorderDefault))
                    pe.Graphics.DrawLine(pen, 0, 0, _navBar.Width, 0);
            };

            // Back button
            _btnBack.Text     = "◀  Back";
            _btnBack.Size     = new System.Drawing.Size(100, 36);
            _btnBack.Location = new System.Drawing.Point(16, 10);
            _btnBack.Click   += new System.EventHandler(btnBack_Click);
            Theme.ThemeHelper.ApplyButtonStyle(_btnBack, Theme.ThemeHelper.ButtonStyle.Ghost);

            // Next button
            _btnNext.Text     = "Next  ▶";
            _btnNext.Size     = new System.Drawing.Size(100, 36);
            _btnNext.Anchor   = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            _btnNext.Click   += new System.EventHandler(btnNext_Click);
            Theme.ThemeHelper.ApplyButtonStyle(_btnNext, Theme.ThemeHelper.ButtonStyle.Primary);

            // Finalize button (last page only)
            _btnFinalize.Text    = "Finalize & Export  ✓";
            _btnFinalize.Size    = new System.Drawing.Size(180, 36);
            _btnFinalize.Anchor  = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            _btnFinalize.Visible = false;
            _btnFinalize.Click  += new System.EventHandler(btnFinalize_Click);
            Theme.ThemeHelper.ApplyButtonStyle(_btnFinalize, Theme.ThemeHelper.ButtonStyle.Primary);

            // Save & Close button (always visible)
            _btnSaveClose.Text    = "Save & Close";
            _btnSaveClose.Size    = new System.Drawing.Size(120, 36);
            _btnSaveClose.Anchor  = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            _btnSaveClose.Click  += new System.EventHandler(btnSaveClose_Click);
            Theme.ThemeHelper.ApplyButtonStyle(_btnSaveClose, Theme.ThemeHelper.ButtonStyle.Secondary);

            // Saved indicator label
            _lblSaved.Text      = string.Empty;
            _lblSaved.Font      = Theme.AppFonts.Caption;
            _lblSaved.ForeColor = Theme.AppColors.StatusSuccess;
            _lblSaved.AutoSize  = true;
            _lblSaved.Location  = new System.Drawing.Point(130, 20);
            _lblSaved.BackColor = System.Drawing.Color.Transparent;

            _navBar.Controls.AddRange(new System.Windows.Forms.Control[]
                { _btnBack, _btnNext, _btnFinalize, _btnSaveClose, _lblSaved });

            // ── Page Host (fills remaining space) ────────────────────
            _pageHost.Dock      = System.Windows.Forms.DockStyle.Fill;
            _pageHost.BackColor = Theme.AppColors.SurfaceBase;
            _pageHost.AutoScroll = true;

            // ── Compose ───────────────────────────────────────────────
            this.Controls.Add(_pageHost);
            this.Controls.Add(_navBar);
            this.Controls.Add(_progressPanel);
            this.Dock = System.Windows.Forms.DockStyle.Fill;

            this.ResumeLayout(false);
        }

        // Called after layout so right-anchored buttons get correct positions
        protected override void OnLayout(System.Windows.Forms.LayoutEventArgs e)
        {
            base.OnLayout(e);
            if (_navBar == null) return;
            int rightEdge = _navBar.Width - 16;
            _btnFinalize.Location  = new System.Drawing.Point(rightEdge - _btnFinalize.Width, 10);
            _btnNext.Location      = new System.Drawing.Point(rightEdge - _btnNext.Width, 10);
            _btnSaveClose.Location = new System.Drawing.Point(
                _btnFinalize.Left - _btnSaveClose.Width - 12, 10);
        }
    }
}
