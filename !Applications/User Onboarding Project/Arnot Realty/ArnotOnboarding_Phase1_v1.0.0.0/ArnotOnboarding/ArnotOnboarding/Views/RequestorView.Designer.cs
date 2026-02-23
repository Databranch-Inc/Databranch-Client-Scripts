namespace ArnotOnboarding.Views
{
    partial class RequestorView
    {
        private System.ComponentModel.IContainer components = null;

        private System.Windows.Forms.Label  _pageHeader;
        private System.Windows.Forms.Label  _pageSubtitle;
        private System.Windows.Forms.Label  _lblName;
        private System.Windows.Forms.Label  _lblTitle;
        private System.Windows.Forms.Label  _lblPhone;
        private System.Windows.Forms.Label  _lblEmail;
        private System.Windows.Forms.Label  _lblDepartment;
        private System.Windows.Forms.TextBox _txtName;
        private System.Windows.Forms.TextBox _txtTitle;
        private System.Windows.Forms.TextBox _txtPhone;
        private System.Windows.Forms.TextBox _txtEmail;
        private System.Windows.Forms.TextBox _txtDepartment;
        private System.Windows.Forms.Label  _lblSaved;
        private System.Windows.Forms.Panel  _formPanel;

        protected override void Dispose(bool disposing) { if (disposing && components != null) components.Dispose(); base.Dispose(disposing); }

        private void InitializeComponent()
        {
            _formPanel   = new System.Windows.Forms.Panel();
            _pageHeader  = new System.Windows.Forms.Label();
            _pageSubtitle = new System.Windows.Forms.Label();
            _lblName     = new System.Windows.Forms.Label();
            _lblTitle    = new System.Windows.Forms.Label();
            _lblPhone    = new System.Windows.Forms.Label();
            _lblEmail    = new System.Windows.Forms.Label();
            _lblDepartment = new System.Windows.Forms.Label();
            _txtName     = new System.Windows.Forms.TextBox();
            _txtTitle    = new System.Windows.Forms.TextBox();
            _txtPhone    = new System.Windows.Forms.TextBox();
            _txtEmail    = new System.Windows.Forms.TextBox();
            _txtDepartment = new System.Windows.Forms.TextBox();
            _lblSaved    = new System.Windows.Forms.Label();

            _formPanel.SuspendLayout();
            this.SuspendLayout();

            // ── Form Panel ────────────────────────────────────────────
            _formPanel.Dock      = System.Windows.Forms.DockStyle.Fill;
            _formPanel.BackColor = Theme.AppColors.SurfaceBase;
            _formPanel.AutoScroll = true;

            // ── Header ────────────────────────────────────────────────
            _pageHeader.Text      = "My Information";
            _pageHeader.Font      = Theme.AppFonts.Heading1;
            _pageHeader.ForeColor = Theme.AppColors.TextPrimary;
            _pageHeader.AutoSize  = true;
            _pageHeader.Location  = new System.Drawing.Point(48, 40);

            _pageSubtitle.Text      = "This information pre-fills the Requestor section of every onboarding wizard.";
            _pageSubtitle.Font      = Theme.AppFonts.Body;
            _pageSubtitle.ForeColor = Theme.AppColors.TextMuted;
            _pageSubtitle.AutoSize  = true;
            _pageSubtitle.Location  = new System.Drawing.Point(48, 72);

            // ── Fields (2-column-ish layout at fixed coords) ──────────
            int lx = 48, fx = 200, fw = 340, fh = 28, rowH = 48, startY = 130;

            SetupLabel(_lblName,       "Full Name",   lx, startY);
            SetupField(_txtName,       fx, startY,    fw, fh);
            SetupLabel(_lblTitle,      "Job Title",   lx, startY + rowH);
            SetupField(_txtTitle,      fx, startY + rowH, fw, fh);
            SetupLabel(_lblDepartment, "Department",  lx, startY + rowH * 2);
            SetupField(_txtDepartment, fx, startY + rowH * 2, fw, fh);
            SetupLabel(_lblPhone,      "Phone",       lx, startY + rowH * 3);
            SetupField(_txtPhone,      fx, startY + rowH * 3, fw, fh);
            SetupLabel(_lblEmail,      "Email",       lx, startY + rowH * 4);
            SetupField(_txtEmail,      fx, startY + rowH * 4, fw, fh);

            // Saved indicator
            _lblSaved.Text      = string.Empty;
            _lblSaved.Font      = Theme.AppFonts.Caption;
            _lblSaved.ForeColor = Theme.AppColors.StatusSuccess;
            _lblSaved.AutoSize  = true;
            _lblSaved.Location  = new System.Drawing.Point(fx, startY + rowH * 5 + 8);

            _formPanel.Controls.AddRange(new System.Windows.Forms.Control[]
            {
                _pageHeader, _pageSubtitle,
                _lblName, _txtName, _lblTitle, _txtTitle,
                _lblDepartment, _txtDepartment, _lblPhone, _txtPhone,
                _lblEmail, _txtEmail, _lblSaved
            });

            this.Controls.Add(_formPanel);
            this.Dock = System.Windows.Forms.DockStyle.Fill;

            _formPanel.ResumeLayout(false);
            this.ResumeLayout(false);
        }

        private void SetupLabel(System.Windows.Forms.Label lbl, string text, int x, int y)
        {
            lbl.Text      = text;
            lbl.Font      = Theme.AppFonts.LabelBold;
            lbl.ForeColor = Theme.AppColors.TextSecondary;
            lbl.AutoSize  = false;
            lbl.Size      = new System.Drawing.Size(140, 28);
            lbl.Location  = new System.Drawing.Point(x, y);
            lbl.TextAlign = System.Drawing.ContentAlignment.MiddleRight;
        }

        private void SetupField(System.Windows.Forms.TextBox txt, int x, int y, int w, int h)
        {
            txt.Location  = new System.Drawing.Point(x + 12, y);
            txt.Size      = new System.Drawing.Size(w, h);
            txt.BackColor = Theme.AppColors.SurfaceVoid;
            txt.ForeColor = Theme.AppColors.TextPrimary;
            txt.BorderStyle = System.Windows.Forms.BorderStyle.FixedSingle;
            txt.Font      = Theme.AppFonts.Body;
        }
    }
}
