// =============================================================
// ArnotOnboarding — WizardView.Designer.cs  v1.3.1.0
// Uses TableLayoutPanel for deterministic 3-row layout:
//   Row 0 (fixed 60px):  Progress bar
//   Row 1 (fill):        Page host — scrollable
//   Row 2 (fixed 56px):  Nav bar (Back/Next)
// This eliminates all Dock-order ambiguity and clipping issues.
// =============================================================
namespace ArnotOnboarding.Views
{
    partial class WizardView
    {
        private System.ComponentModel.IContainer components = null;

        private System.Windows.Forms.TableLayoutPanel _layout;
        private System.Windows.Forms.Panel  _progressPanel;
        private System.Windows.Forms.Panel  _pageHost;
        private System.Windows.Forms.Panel  _navBar;
        private System.Windows.Forms.Button _btnBack;
        private System.Windows.Forms.Button _btnNext;
        private System.Windows.Forms.Button _btnFinalize;
        private System.Windows.Forms.Button _btnSaveClose;
        private System.Windows.Forms.Label  _lblSaved;

        private void InitializeComponent()
        {
            _layout        = new System.Windows.Forms.TableLayoutPanel();
            _progressPanel = new System.Windows.Forms.Panel();
            _pageHost      = new System.Windows.Forms.Panel();
            _navBar        = new System.Windows.Forms.Panel();
            _btnBack       = new System.Windows.Forms.Button();
            _btnNext       = new System.Windows.Forms.Button();
            _btnFinalize   = new System.Windows.Forms.Button();
            _btnSaveClose  = new System.Windows.Forms.Button();
            _lblSaved      = new System.Windows.Forms.Label();

            this.SuspendLayout();

            // ── TableLayoutPanel — 3 rows, 1 col ─────────────────────
            _layout.Dock        = System.Windows.Forms.DockStyle.Fill;
            _layout.ColumnCount = 1;
            _layout.RowCount    = 3;
            _layout.ColumnStyles.Add(new System.Windows.Forms.ColumnStyle(
                System.Windows.Forms.SizeType.Percent, 100F));
            // Row 0: progress bar — fixed height
            _layout.RowStyles.Add(new System.Windows.Forms.RowStyle(
                System.Windows.Forms.SizeType.Absolute, PROGRESS_HEIGHT));
            // Row 1: page content — takes all remaining space
            _layout.RowStyles.Add(new System.Windows.Forms.RowStyle(
                System.Windows.Forms.SizeType.Percent, 100F));
            // Row 2: nav bar — fixed height
            _layout.RowStyles.Add(new System.Windows.Forms.RowStyle(
                System.Windows.Forms.SizeType.Absolute, NAV_BAR_HEIGHT));
            _layout.Padding = new System.Windows.Forms.Padding(0);
            _layout.Margin  = new System.Windows.Forms.Padding(0);
            _layout.CellBorderStyle = System.Windows.Forms.TableLayoutPanelCellBorderStyle.None;
            _layout.BackColor = Theme.AppColors.SurfaceBase;

            // ── Progress Panel (row 0) ────────────────────────────────
            _progressPanel.Dock      = System.Windows.Forms.DockStyle.Fill;
            _progressPanel.BackColor = Theme.AppColors.SurfaceRaised;
            _progressPanel.Margin    = new System.Windows.Forms.Padding(0);
            _progressPanel.Paint    += new System.Windows.Forms.PaintEventHandler(progressPanel_Paint);

            // ── Page Host (row 1) — the scrollable content area ───────
            // AutoScroll=true here, NOT on the child page.
            // Child pages use Dock=Fill and place controls with absolute coords.
            // The host scrolls; the child just renders.
            _pageHost.Dock        = System.Windows.Forms.DockStyle.Fill;
            _pageHost.BackColor   = Theme.AppColors.SurfaceBase;
            _pageHost.AutoScroll  = true;
            _pageHost.Margin      = new System.Windows.Forms.Padding(0);
            // Top padding of 4px provides a physical gap between the progress
            // panel border and the first rendered row of content. Without this,
            // the panel border and the first label overlap by a few pixels.
            _pageHost.Padding     = new System.Windows.Forms.Padding(0, 4, 0, 0);

            // ── Nav Bar (row 2) ────────────────────────────────────────
            _navBar.Dock      = System.Windows.Forms.DockStyle.Fill;
            _navBar.BackColor = Theme.AppColors.SurfaceRaised;
            _navBar.Margin    = new System.Windows.Forms.Padding(0);
            _navBar.Paint += (s, pe) => {
                using (var pen = new System.Drawing.Pen(Theme.AppColors.BorderDefault))
                    pe.Graphics.DrawLine(pen, 0, 0, _navBar.Width, 0);
            };

            // Back
            _btnBack.Text     = "◀  Back";
            _btnBack.Size     = new System.Drawing.Size(100, 36);
            _btnBack.Location = new System.Drawing.Point(16, 10);
            _btnBack.Click   += new System.EventHandler(btnBack_Click);
            Theme.ThemeHelper.ApplyButtonStyle(_btnBack, Theme.ThemeHelper.ButtonStyle.Ghost);

            // Saved label
            _lblSaved.Text      = string.Empty;
            _lblSaved.Font      = Theme.AppFonts.Caption;
            _lblSaved.ForeColor = Theme.AppColors.StatusSuccess;
            _lblSaved.AutoSize  = true;
            _lblSaved.Location  = new System.Drawing.Point(130, 20);
            _lblSaved.BackColor = System.Drawing.Color.Transparent;

            // Next
            _btnNext.Text    = "Next  ▶";
            _btnNext.Size    = new System.Drawing.Size(100, 36);
            _btnNext.Click  += new System.EventHandler(btnNext_Click);
            Theme.ThemeHelper.ApplyButtonStyle(_btnNext, Theme.ThemeHelper.ButtonStyle.Primary);

            // Finalize
            _btnFinalize.Text    = "Finalize & Export  ✓";
            _btnFinalize.Size    = new System.Drawing.Size(180, 36);
            _btnFinalize.Visible = false;
            _btnFinalize.Click  += new System.EventHandler(btnFinalize_Click);
            Theme.ThemeHelper.ApplyButtonStyle(_btnFinalize, Theme.ThemeHelper.ButtonStyle.Primary);

            // Save & Close
            _btnSaveClose.Text   = "Save & Close";
            _btnSaveClose.Size   = new System.Drawing.Size(120, 36);
            _btnSaveClose.Click += new System.EventHandler(btnSaveClose_Click);
            Theme.ThemeHelper.ApplyButtonStyle(_btnSaveClose, Theme.ThemeHelper.ButtonStyle.Secondary);

            _navBar.Controls.AddRange(new System.Windows.Forms.Control[]
                { _btnBack, _btnNext, _btnFinalize, _btnSaveClose, _lblSaved });

            // ── Assemble TableLayoutPanel ─────────────────────────────
            _layout.Controls.Add(_progressPanel, 0, 0);
            _layout.Controls.Add(_pageHost,      0, 1);
            _layout.Controls.Add(_navBar,        0, 2);

            // ── WizardView ────────────────────────────────────────────
            this.Controls.Add(_layout);
            this.Dock = System.Windows.Forms.DockStyle.Fill;
            this.ResumeLayout(false);
        }

        protected override void OnLayout(System.Windows.Forms.LayoutEventArgs e)
        {
            base.OnLayout(e);
            if (_navBar == null) return;
            int right = _navBar.Width - 16;
            _btnFinalize.Location  = new System.Drawing.Point(right - _btnFinalize.Width, 10);
            _btnNext.Location      = new System.Drawing.Point(right - _btnNext.Width, 10);
            _btnSaveClose.Location = new System.Drawing.Point(
                System.Math.Min(_btnNext.Left, _btnFinalize.Left) - _btnSaveClose.Width - 12, 10);
        }
    }
}
