// =============================================================
// ArnotOnboarding — DraftListView.Designer.cs
// Version    : 1.0.0.0
// =============================================================

namespace ArnotOnboarding.Views
{
    partial class DraftListView
    {
        private System.ComponentModel.IContainer components = null;

        // ── Controls ─────────────────────────────────────────────────
        private System.Windows.Forms.Panel      _headerPanel;
        private System.Windows.Forms.Label      _pageTitle;
        private System.Windows.Forms.Label      _pageSubtitle;
        private System.Windows.Forms.Panel      _toolbarPanel;
        private System.Windows.Forms.Button     _btnResume;
        private System.Windows.Forms.Button     _btnDelete;
        private System.Windows.Forms.Button     _btnExport;
        private System.Windows.Forms.Button     _btnImport;
        private System.Windows.Forms.Button     _btnRefresh;
        private System.Windows.Forms.ListView   _listView;
        private System.Windows.Forms.ColumnHeader _colName;
        private System.Windows.Forms.ColumnHeader _colStarted;
        private System.Windows.Forms.ColumnHeader _colModified;
        private System.Windows.Forms.Panel      _emptyPanel;
        private System.Windows.Forms.Label      _emptyLabel;
        private System.Windows.Forms.Label      _emptySubLabel;
        private System.Windows.Forms.Panel      _detailPanel;
        private System.Windows.Forms.Label      _detailName;
        private System.Windows.Forms.Label      _detailStarted;
        private System.Windows.Forms.Label      _detailModified;
        private System.Windows.Forms.Label      _detailPage;

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
            _listView      = new System.Windows.Forms.ListView();
            _colName       = new System.Windows.Forms.ColumnHeader();
            _colStarted    = new System.Windows.Forms.ColumnHeader();
            _colModified   = new System.Windows.Forms.ColumnHeader();
            _emptyPanel    = new System.Windows.Forms.Panel();
            _emptyLabel    = new System.Windows.Forms.Label();
            _emptySubLabel = new System.Windows.Forms.Label();
            _detailPanel   = new System.Windows.Forms.Panel();
            _detailName    = new System.Windows.Forms.Label();
            _detailStarted  = new System.Windows.Forms.Label();
            _detailModified = new System.Windows.Forms.Label();
            _detailPage     = new System.Windows.Forms.Label();

            this.SuspendLayout();

            // ── Header Panel ─────────────────────────────────────────
            _headerPanel.Dock      = System.Windows.Forms.DockStyle.Top;
            _headerPanel.Height    = 72;
            _headerPanel.BackColor = Theme.AppColors.SurfaceBase;
            _headerPanel.Padding   = new System.Windows.Forms.Padding(32, 0, 24, 0);

            _pageTitle.Text      = "In Progress";
            _pageTitle.Font      = Theme.AppFonts.Heading1;
            _pageTitle.ForeColor = Theme.AppColors.TextPrimary;
            _pageTitle.AutoSize  = true;
            _pageTitle.Location  = new System.Drawing.Point(32, 16);

            _pageSubtitle.Text      = "Saved drafts — resume anytime, even after closing the app.";
            _pageSubtitle.Font      = Theme.AppFonts.Body;
            _pageSubtitle.ForeColor = Theme.AppColors.TextMuted;
            _pageSubtitle.AutoSize  = true;
            _pageSubtitle.Location  = new System.Drawing.Point(32, 46);

            _headerPanel.Controls.Add(_pageTitle);
            _headerPanel.Controls.Add(_pageSubtitle);

            // ── Toolbar Panel ─────────────────────────────────────────
            _toolbarPanel.Dock      = System.Windows.Forms.DockStyle.Top;
            _toolbarPanel.Height    = 48;
            _toolbarPanel.BackColor = Theme.AppColors.SurfaceRaised;
            _toolbarPanel.Padding   = new System.Windows.Forms.Padding(28, 0, 24, 0);

            SetupToolbarButton(_btnResume,  "▶  Resume",  8,   true,  Theme.ThemeHelper.ButtonStyle.Primary);
            SetupToolbarButton(_btnDelete,  "✕  Delete",  122, false, Theme.ThemeHelper.ButtonStyle.Danger);
            SetupToolbarButton(_btnExport,  "↑  Export",  236, false, Theme.ThemeHelper.ButtonStyle.Ghost);
            SetupToolbarButton(_btnImport,  "↓  Import",  350, false, Theme.ThemeHelper.ButtonStyle.Ghost);
            SetupToolbarButton(_btnRefresh, "↺  Refresh", 464, false, Theme.ThemeHelper.ButtonStyle.Ghost);

            _btnResume.Click  += new System.EventHandler(this.btnResume_Click);
            _btnDelete.Click  += new System.EventHandler(this.btnDelete_Click);
            _btnExport.Click  += new System.EventHandler(this.btnExport_Click);
            _btnImport.Click  += new System.EventHandler(this.btnImport_Click);
            _btnRefresh.Click += new System.EventHandler(this.btnRefresh_Click);

            _toolbarPanel.Controls.AddRange(new System.Windows.Forms.Control[]
                { _btnResume, _btnDelete, _btnExport, _btnImport, _btnRefresh });

            // ── Detail Panel (right side, shown on selection) ─────────
            _detailPanel.Dock      = System.Windows.Forms.DockStyle.Right;
            _detailPanel.Width     = 260;
            _detailPanel.BackColor = Theme.AppColors.SurfaceCard;
            _detailPanel.Visible   = false;
            _detailPanel.Padding   = new System.Windows.Forms.Padding(20, 24, 20, 20);

            // top border
            _detailPanel.Paint += (s, pe) => {
                using (var pen = new System.Drawing.Pen(Theme.AppColors.BorderDefault))
                    pe.Graphics.DrawLine(pen, 0, 0, 0, _detailPanel.Height);
            };

            _detailName.AutoSize  = false;
            _detailName.Size      = new System.Drawing.Size(220, 40);
            _detailName.Location  = new System.Drawing.Point(20, 24);
            _detailName.Font      = Theme.AppFonts.Heading2;
            _detailName.ForeColor = Theme.AppColors.TextPrimary;
            _detailName.Text      = string.Empty;

            SetupDetailLabel(_detailStarted,  new System.Drawing.Point(20, 72));
            SetupDetailLabel(_detailModified, new System.Drawing.Point(20, 96));
            SetupDetailLabel(_detailPage,     new System.Drawing.Point(20, 124));

            _detailPanel.Controls.AddRange(new System.Windows.Forms.Control[]
                { _detailName, _detailStarted, _detailModified, _detailPage });

            // ── ListView ──────────────────────────────────────────────
            _listView.Dock           = System.Windows.Forms.DockStyle.Fill;
            _listView.View           = System.Windows.Forms.View.Details;
            _listView.FullRowSelect  = true;
            _listView.MultiSelect    = false;
            _listView.GridLines      = false;
            _listView.BorderStyle    = System.Windows.Forms.BorderStyle.None;
            _listView.BackColor      = Theme.AppColors.SurfaceBase;
            _listView.ForeColor      = Theme.AppColors.TextSecondary;
            _listView.Font           = Theme.AppFonts.Body;
            _listView.HeaderStyle    = System.Windows.Forms.ColumnHeaderStyle.Nonclickable;
            _listView.ShowItemToolTips = true;
            _listView.Visible        = false;

            _colName.Text     = "Employee";
            _colName.Width    = 260;
            _colStarted.Text  = "Started";
            _colStarted.Width = 120;
            _colModified.Text = "Last Modified";
            _colModified.Width = 200;

            _listView.Columns.AddRange(new System.Windows.Forms.ColumnHeader[]
                { _colName, _colStarted, _colModified });

            _listView.SelectedIndexChanged += new System.EventHandler(this.listView_SelectedIndexChanged);
            _listView.DoubleClick          += new System.EventHandler(this.listView_DoubleClick);

            // ── Empty State Panel ─────────────────────────────────────
            _emptyPanel.Dock      = System.Windows.Forms.DockStyle.Fill;
            _emptyPanel.BackColor = Theme.AppColors.SurfaceBase;
            _emptyPanel.Visible   = true;

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

            // ── Compose Layout ────────────────────────────────────────
            // Note: DockStyle.Fill controls must be added LAST (or before Top/Bottom)
            // so they correctly fill remaining space.
            this.Controls.Add(_listView);
            this.Controls.Add(_emptyPanel);
            this.Controls.Add(_detailPanel);
            this.Controls.Add(_toolbarPanel);
            this.Controls.Add(_headerPanel);

            this.Dock = System.Windows.Forms.DockStyle.Fill;
            this.ResumeLayout(false);
        }

        private void SetupToolbarButton(System.Windows.Forms.Button btn, string text, int x,
            bool isPrimary, Theme.ThemeHelper.ButtonStyle style)
        {
            btn.Text     = text;
            btn.Size     = new System.Drawing.Size(106, 32);
            btn.Location = new System.Drawing.Point(x + 28, 8);
            btn.Enabled  = !isPrimary ? false : true;
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
        }
    }
}
