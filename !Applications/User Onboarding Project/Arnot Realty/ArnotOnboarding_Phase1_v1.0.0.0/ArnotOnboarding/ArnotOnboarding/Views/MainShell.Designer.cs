// =============================================================
// ArnotOnboarding — MainShell.Designer.cs
// Auto-generated designer backing for MainShell.cs
// =============================================================

namespace ArnotOnboarding.Views
{
    partial class MainShell
    {
        private System.ComponentModel.IContainer components = null;

        // Controls
        private System.Windows.Forms.Panel _navPanel;
        private System.Windows.Forms.Panel _contentPanel;

        protected override void Dispose(bool disposing)
        {
            if (disposing && components != null)
                components.Dispose();
            base.Dispose(disposing);
        }

        private void InitializeComponent()
        {
            this._navPanel     = new System.Windows.Forms.Panel();
            this._contentPanel = new System.Windows.Forms.Panel();
            this.SuspendLayout();

            // ── Nav Panel ─────────────────────────────────────────────
            this._navPanel.Dock        = System.Windows.Forms.DockStyle.Left;
            this._navPanel.Width       = NAV_WIDTH;
            this._navPanel.BackColor   = Theme.AppColors.SurfaceRaised;
            this._navPanel.Paint      += new System.Windows.Forms.PaintEventHandler(this.navPanel_Paint);
            this._navPanel.MouseClick += new System.Windows.Forms.MouseEventHandler(this.navPanel_MouseClick);
            this._navPanel.MouseMove  += new System.Windows.Forms.MouseEventHandler(this.navPanel_MouseMove);

            // ── Content Panel ─────────────────────────────────────────
            this._contentPanel.Dock      = System.Windows.Forms.DockStyle.Fill;
            this._contentPanel.BackColor = Theme.AppColors.SurfaceBase;
            this._contentPanel.Padding   = new System.Windows.Forms.Padding(0);

            // ── Form ──────────────────────────────────────────────────
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize    = new System.Drawing.Size(1100, 760);
            this.Controls.Add(this._contentPanel);
            this.Controls.Add(this._navPanel);
            this.Load         += new System.EventHandler(this.MainShell_Load);
            this.FormClosing  += new System.Windows.Forms.FormClosingEventHandler(this.MainShell_FormClosing);

            this.ResumeLayout(false);
        }
    }
}
