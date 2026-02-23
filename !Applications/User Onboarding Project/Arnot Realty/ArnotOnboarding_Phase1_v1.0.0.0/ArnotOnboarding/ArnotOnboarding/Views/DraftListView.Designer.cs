namespace ArnotOnboarding.Views
{
    partial class DraftListView
    {
        private System.ComponentModel.IContainer components = null;
        protected override void Dispose(bool disposing) { if (disposing && components != null) components.Dispose(); base.Dispose(disposing); }
        private void InitializeComponent()
        {
            var lbl = new System.Windows.Forms.Label
            {
                Text = "In Progress — Phase 2",
                Font = Theme.AppFonts.Heading2,
                ForeColor = Theme.AppColors.TextMuted,
                AutoSize = true,
                Location = new System.Drawing.Point(40, 40)
            };
            this.Controls.Add(lbl);
            this.Dock = System.Windows.Forms.DockStyle.Fill;
            this.BackColor = Theme.AppColors.SurfaceBase;
        }
    }
}
