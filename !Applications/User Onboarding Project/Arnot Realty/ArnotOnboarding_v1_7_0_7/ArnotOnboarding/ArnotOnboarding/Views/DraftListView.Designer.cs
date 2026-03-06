// =============================================================
// ArnotOnboarding — DraftListView.Designer.cs
// Version    : 1.5.8.0
// =============================================================

namespace ArnotOnboarding.Views
{
    partial class DraftListView
    {
        private System.ComponentModel.IContainer components = null;

        private System.Windows.Forms.Panel               _headerPanel;
        private System.Windows.Forms.Label               _pageTitle;
        private System.Windows.Forms.Label               _pageSubtitle;
        private System.Windows.Forms.Panel               _toolbarPanel;
        private System.Windows.Forms.Button              _btnResume;
        private System.Windows.Forms.Button              _btnDelete;
        private System.Windows.Forms.Button              _btnExport;
        private System.Windows.Forms.Button              _btnImport;
        private System.Windows.Forms.Button              _btnRefresh;
        private System.Windows.Forms.DataGridView        _grid;
        private System.Windows.Forms.DataGridViewTextBoxColumn _colName;
        private System.Windows.Forms.DataGridViewTextBoxColumn _colStarted;
        private System.Windows.Forms.DataGridViewTextBoxColumn _colModified;
        private System.Windows.Forms.Panel               _emptyPanel;
        private System.Windows.Forms.Label               _emptyLabel;
        private System.Windows.Forms.Label               _emptySubLabel;
        private System.Windows.Forms.Panel               _detailPanel;
        private System.Windows.Forms.Label               _detailName;
        private System.Windows.Forms.Label               _detailStarted;
        private System.Windows.Forms.Label               _detailModified;
        private System.Windows.Forms.Label               _detailPage;
        private System.Windows.Forms.Label               _detailEmpty;

        protected override void Dispose(bool disposing)
        {
            if (disposing && components != null) components.Dispose();
            base.Dispose(disposing);
        }

        private void InitializeComponent()
        {
            _headerPanel   = new System.Windows.Forms.Panel();
            _pageTitle     = new System.Windows.Forms.Label();
            _pageSubtitle  = new System.Windows.Forms.Label();
            _toolbarPanel  = new System.Windows.Forms.Panel();
            _btnResume     = new System.Windows.Forms.Button();
            _btnDelete     = new System.Windows.Forms.Button();
            _btnExport     = new System.Windows.Forms.Button();
            _btnImport     = new System.Windows.Forms.Button();
            _btnRefresh    = new System.Windows.Forms.Button();
            _grid          = new System.Windows.Forms.DataGridView();
            _colName       = new System.Windows.Forms.DataGridViewTextBoxColumn();
            _colStarted    = new System.Windows.Forms.DataGridViewTextBoxColumn();
            _colModified   = new System.Windows.Forms.DataGridViewTextBoxColumn();
            _emptyPanel    = new System.Windows.Forms.Panel();
            _emptyLabel    = new System.Windows.Forms.Label();
            _emptySubLabel = new System.Windows.Forms.Label();
            _detailPanel   = new System.Windows.Forms.Panel();
            _detailName    = new System.Windows.Forms.Label();
            _detailStarted  = new System.Windows.Forms.Label();
            _detailModified = new System.Windows.Forms.Label();
            _detailPage     = new System.Windows.Forms.Label();
            _detailEmpty    = new System.Windows.Forms.Label();

            this.SuspendLayout();

            // ── Page Header ───────────────────────────────────────────
            _headerPanel.Dock      = System.Windows.Forms.DockStyle.Top;
            _headerPanel.Height    = 72;
            _headerPanel.BackColor = Theme.AppColors.SurfaceBase;

            _pageTitle.Text      = "In Progress";
            _pageTitle.Font      = Theme.AppFonts.Heading1;
            _pageTitle.ForeColor = Theme.AppColors.TextPrimary;
            _pageTitle.AutoSize  = true;
            _pageTitle.Location  = new System.Drawing.Point(32, 14);

            _pageSubtitle.Text      = "Saved drafts \u2014 resume anytime, even after closing the app.";
            _pageSubtitle.Font      = Theme.AppFonts.Body;
            _pageSubtitle.ForeColor = Theme.AppColors.TextMuted;
            _pageSubtitle.AutoSize  = true;
            _pageSubtitle.Location  = new System.Drawing.Point(32, 44);

            _headerPanel.Controls.Add(_pageTitle);
            _headerPanel.Controls.Add(_pageSubtitle);

            // ── Toolbar ───────────────────────────────────────────────
            _toolbarPanel.Dock      = System.Windows.Forms.DockStyle.Top;
            _toolbarPanel.Height    = 52;
            _toolbarPanel.BackColor = Theme.AppColors.SurfaceRaised;

            SetupButton(_btnResume,  "\u25b6  Resume",  8,   Theme.ThemeHelper.ButtonStyle.Primary);
            SetupButton(_btnDelete,  "\u2715  Delete",  122, Theme.ThemeHelper.ButtonStyle.Danger);
            SetupButton(_btnExport,  "\u2191  Export",  236, Theme.ThemeHelper.ButtonStyle.Ghost);
            SetupButton(_btnImport,  "\u2193  Import",  350, Theme.ThemeHelper.ButtonStyle.Ghost);
            SetupButton(_btnRefresh, "\u21ba  Refresh", 464, Theme.ThemeHelper.ButtonStyle.Ghost);

            _btnResume.Enabled  = false;
            _btnDelete.Enabled  = false;
            _btnExport.Enabled  = false;
            _btnImport.Enabled  = true;
            _btnRefresh.Enabled = true;

            _btnResume.Click  += new System.EventHandler(this.btnResume_Click);
            _btnDelete.Click  += new System.EventHandler(this.btnDelete_Click);
            _btnExport.Click  += new System.EventHandler(this.btnExport_Click);
            _btnImport.Click  += new System.EventHandler(this.btnImport_Click);
            _btnRefresh.Click += new System.EventHandler(this.btnRefresh_Click);

            _toolbarPanel.Controls.AddRange(new System.Windows.Forms.Control[]
                { _btnResume, _btnDelete, _btnExport, _btnImport, _btnRefresh });

            // ── Detail Panel (always visible, right side) ─────────────
            _detailPanel.Dock      = System.Windows.Forms.DockStyle.Right;
            _detailPanel.Width     = 260;
            _detailPanel.BackColor = Theme.AppColors.SurfaceCard;
            _detailPanel.Padding   = new System.Windows.Forms.Padding(20, 24, 20, 20);

            _detailPanel.Paint += (s, pe) => {
                using (var pen = new System.Drawing.Pen(Theme.AppColors.BorderDefault))
                    pe.Graphics.DrawLine(pen, 0, 0, 0, _detailPanel.Height);
            };

            _detailEmpty.Text      = "Select a draft\nto see details";
            _detailEmpty.Font      = Theme.AppFonts.Body;
            _detailEmpty.ForeColor = Theme.AppColors.TextDim;
            _detailEmpty.AutoSize  = false;
            _detailEmpty.Size      = new System.Drawing.Size(220, 60);
            _detailEmpty.Location  = new System.Drawing.Point(20, 24);
            _detailEmpty.Visible   = true;

            _detailName.AutoSize  = false;
            _detailName.Size      = new System.Drawing.Size(220, 40);
            _detailName.Location  = new System.Drawing.Point(20, 24);
            _detailName.Font      = Theme.AppFonts.Heading2;
            _detailName.ForeColor = Theme.AppColors.TextPrimary;
            _detailName.Visible   = false;

            SetupDetailLabel(_detailStarted,  new System.Drawing.Point(20, 72));
            SetupDetailLabel(_detailModified, new System.Drawing.Point(20, 96));
            SetupDetailLabel(_detailPage,     new System.Drawing.Point(20, 124));

            _detailPanel.Controls.AddRange(new System.Windows.Forms.Control[]
                { _detailEmpty, _detailName, _detailStarted, _detailModified, _detailPage });

            // ── DataGridView ──────────────────────────────────────────
            _colName.HeaderText      = "Employee";
            _colName.ReadOnly        = true;
            _colName.SortMode        = System.Windows.Forms.DataGridViewColumnSortMode.NotSortable;

            _colStarted.HeaderText   = "Started";
            _colStarted.ReadOnly     = true;
            _colStarted.SortMode     = System.Windows.Forms.DataGridViewColumnSortMode.NotSortable;

            _colModified.HeaderText  = "Last Modified";
            _colModified.ReadOnly    = true;
            _colModified.SortMode    = System.Windows.Forms.DataGridViewColumnSortMode.NotSortable;

            _grid.Dock                          = System.Windows.Forms.DockStyle.Fill;
            _grid.AllowUserToAddRows            = false;
            _grid.AllowUserToDeleteRows         = false;
            _grid.AllowUserToResizeRows         = false;
            _grid.AllowUserToResizeColumns      = false;
            _grid.ReadOnly                      = true;
            _grid.SelectionMode                 = System.Windows.Forms.DataGridViewSelectionMode.FullRowSelect;
            _grid.MultiSelect                   = false;
            _grid.RowHeadersVisible             = false;
            _grid.AutoSizeColumnsMode           = System.Windows.Forms.DataGridViewAutoSizeColumnsMode.None;
            _grid.ScrollBars                    = System.Windows.Forms.ScrollBars.Vertical;
            _grid.BorderStyle                   = System.Windows.Forms.BorderStyle.None;
            _grid.CellBorderStyle               = System.Windows.Forms.DataGridViewCellBorderStyle.SingleHorizontal;
            _grid.ColumnHeadersBorderStyle      = System.Windows.Forms.DataGridViewHeaderBorderStyle.Single;
            _grid.BackgroundColor               = Theme.AppColors.SurfaceBase;
            _grid.GridColor                     = Theme.AppColors.BorderSubtle;
            _grid.Font                          = Theme.AppFonts.Body;

            // Row defaults
            _grid.RowTemplate.Height            = 32;
            _grid.RowTemplate.DefaultCellStyle.BackColor   = Theme.AppColors.SurfaceCard;
            _grid.RowTemplate.DefaultCellStyle.ForeColor   = Theme.AppColors.TextSecondary;
            _grid.RowTemplate.DefaultCellStyle.Font        = Theme.AppFonts.Body;
            _grid.RowTemplate.DefaultCellStyle.SelectionBackColor = Theme.AppColors.SurfaceOverlay;
            _grid.RowTemplate.DefaultCellStyle.SelectionForeColor = Theme.AppColors.TextPrimary;
            _grid.RowTemplate.DefaultCellStyle.Padding     = new System.Windows.Forms.Padding(6, 0, 0, 0);

            // Header style
            _grid.ColumnHeadersHeight           = 28;
            _grid.ColumnHeadersHeightSizeMode   = System.Windows.Forms.DataGridViewColumnHeadersHeightSizeMode.DisableResizing;
            _grid.ColumnHeadersDefaultCellStyle.BackColor   = Theme.AppColors.SurfaceRaised;
            _grid.ColumnHeadersDefaultCellStyle.ForeColor   = Theme.AppColors.TextMuted;
            _grid.ColumnHeadersDefaultCellStyle.Font        = Theme.AppFonts.SectionLabel;
            _grid.ColumnHeadersDefaultCellStyle.SelectionBackColor = Theme.AppColors.SurfaceRaised;
            _grid.ColumnHeadersDefaultCellStyle.Padding     = new System.Windows.Forms.Padding(8, 0, 0, 0);

            // Alternating row color
            _grid.AlternatingRowsDefaultCellStyle.BackColor          = Theme.AppColors.SurfaceRaised;
            _grid.AlternatingRowsDefaultCellStyle.SelectionBackColor = Theme.AppColors.SurfaceOverlay;
            _grid.AlternatingRowsDefaultCellStyle.SelectionForeColor = Theme.AppColors.TextPrimary;

            _grid.DefaultCellStyle.BackColor          = Theme.AppColors.SurfaceCard;
            _grid.DefaultCellStyle.ForeColor          = Theme.AppColors.TextSecondary;
            _grid.DefaultCellStyle.SelectionBackColor = Theme.AppColors.SurfaceOverlay;
            _grid.DefaultCellStyle.SelectionForeColor = Theme.AppColors.TextPrimary;
            _grid.DefaultCellStyle.Padding            = new System.Windows.Forms.Padding(6, 0, 0, 0);

            _grid.Columns.AddRange(new System.Windows.Forms.DataGridViewColumn[]
                { _colName, _colStarted, _colModified });

            // ── Empty State Panel ─────────────────────────────────────
            _emptyPanel.Dock      = System.Windows.Forms.DockStyle.Fill;
            _emptyPanel.BackColor = Theme.AppColors.SurfaceBase;

            _emptyLabel.Text      = "No drafts in progress";
            _emptyLabel.Font      = Theme.AppFonts.Heading2;
            _emptyLabel.ForeColor = Theme.AppColors.TextMuted;
            _emptyLabel.AutoSize  = true;
            _emptyLabel.Location  = new System.Drawing.Point(48, 80);

            _emptySubLabel.Text      = "Start a new onboarding from the nav menu.\nDrafts will appear here automatically as you work.";
            _emptySubLabel.Font      = Theme.AppFonts.Body;
            _emptySubLabel.ForeColor = Theme.AppColors.TextDim;
            _emptySubLabel.AutoSize  = true;
            _emptySubLabel.Location  = new System.Drawing.Point(48, 112);

            _emptyPanel.Controls.Add(_emptyLabel);
            _emptyPanel.Controls.Add(_emptySubLabel);

            // ── Layout ────────────────────────────────────────────────
            this.Controls.Add(_grid);
            this.Controls.Add(_emptyPanel);
            this.Controls.Add(_detailPanel);
            this.Controls.Add(_toolbarPanel);
            this.Controls.Add(_headerPanel);

            _emptyPanel.BringToFront(); // covers grid until items loaded

            this.Dock = System.Windows.Forms.DockStyle.Fill;
            this.ResumeLayout(false);
        }

        private void SetupButton(System.Windows.Forms.Button btn, string text, int x,
            Theme.ThemeHelper.ButtonStyle style)
        {
            btn.Text     = text;
            btn.Size     = new System.Drawing.Size(106, 34);
            btn.Location = new System.Drawing.Point(x + 28, 9);
            Theme.ThemeHelper.ApplyButtonStyle(btn, style);
        }

        private void SetupDetailLabel(System.Windows.Forms.Label lbl, System.Drawing.Point loc)
        {
            lbl.AutoSize  = false;
            lbl.Size      = new System.Drawing.Size(220, 20);
            lbl.Location  = loc;
            lbl.Font      = Theme.AppFonts.BodySmall;
            lbl.ForeColor = Theme.AppColors.TextMuted;
            lbl.Text      = string.Empty;
            lbl.Visible   = false;
        }
    }
}
