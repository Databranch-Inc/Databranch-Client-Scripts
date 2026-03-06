// =============================================================
// ArnotOnboardingUtility — Views/MainShell.cs
// Version    : 1.0.2.0
// Author     : Sam Kirsch / Databranch
// Created    : 2026-02-28
// Modified   : 2026-02-28
// Description: Borderless shell. Layout (all via Dock):
//
//   ┌─────────────────────────────────────────────────────┐
//   │  _titleBar  (DockStyle.Top, 32px) — drag+chrome     │
//   ├──────────────┬──────────────────────────────────────┤
//   │              │                                      │
//   │  _navPanel   │  _contentPanel  (DockStyle.Fill)     │
//   │ (Dock.Left)  │  hosts swapped UserControl views     │
//   │              │                                      │
//   └──────────────┴──────────────────────────────────────┘
//
//   WinForms DockStyle resolution order:
//     Controls added LAST get dock priority.
//     So we add: Fill first, Left second, Top LAST.
//   Resize grip: WM_NCHITTEST override on the form edges.
// =============================================================
using System;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using ArnotOnboardingUtility.Managers;
using ArnotOnboardingUtility.Models;
using ArnotOnboardingUtility.Theme;

namespace ArnotOnboardingUtility.Views
{
    public class MainShell : Form
    {
        // ── P/Invoke for native borderless resize ──────────────────────
        [DllImport("user32.dll")]
        private static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);
        [DllImport("user32.dll")]
        private static extern bool ReleaseCapture();
        private const int WM_NCLBUTTONDOWN = 0xA1;
        private const int WM_NCHITTEST     = 0x84;
        private const int HTCLIENT         = 1;
        private const int HTCAPTION        = 2;
        private const int HTLEFT           = 10;
        private const int HTRIGHT          = 11;
        private const int HTTOP            = 12;
        private const int HTTOPLEFT        = 13;
        private const int HTTOPRIGHT       = 14;
        private const int HTBOTTOM         = 15;
        private const int HTBOTTOMLEFT     = 16;
        private const int HTBOTTOMRIGHT    = 17;
        private const int GRIP             = 8;   // resize border thickness

        // ── Resize helpers ────────────────────────────────────────────
        private int GetResizeHT(Point screenPt)
        {
            var c  = PointToClient(screenPt);
            int cw = ClientSize.Width;
            int ch = ClientSize.Height;
            bool left   = c.X <= GRIP;
            bool right  = c.X >= cw - GRIP;
            bool top    = c.Y <= GRIP;
            bool bottom = c.Y >= ch - GRIP;

            if (top    && left)  return HTTOPLEFT;
            if (top    && right) return HTTOPRIGHT;
            if (bottom && left)  return HTBOTTOMLEFT;
            if (bottom && right) return HTBOTTOMRIGHT;
            if (left)            return HTLEFT;
            if (right)           return HTRIGHT;
            if (bottom)          return HTBOTTOM;
            return HTCLIENT;
        }

        private static Cursor HtToCursor(int ht)
        {
            switch (ht)
            {
                case HTTOPLEFT:     case HTBOTTOMRIGHT: return Cursors.SizeNWSE;
                case HTTOPRIGHT:    case HTBOTTOMLEFT:  return Cursors.SizeNESW;
                case HTLEFT:        case HTRIGHT:        return Cursors.SizeWE;
                case HTBOTTOM:                           return Cursors.SizeNS;
                default:                                 return Cursors.Default;
            }
        }

        // ── Layout Constants ──────────────────────────────────────────
        private const int NAV_WIDTH       = 260;
        private const int TITLE_H         = 32;
        private const int NAV_LOGO_H      = 100; // logo zone height in nav
        private const int NAV_ITEM_H      = 34;
        private const int NAV_SECTION_H   = 28;
        private const int FOOTER_H        = 52;

        // ── Nav Targets ───────────────────────────────────────────────
        private enum NavTarget { Landing, StepRunner, LogViewer, Settings }

        // ── State ─────────────────────────────────────────────────────
        private NavTarget _activeNav     = NavTarget.Landing;
        private bool      _aboutHovered  = false;
        private bool      _closeHovered  = false;
        private bool      _minHovered    = false;
        private bool      _maxHovered    = false;
        private bool      _sessionLoaded = false;

        // ── Hit rects (nav panel coords) ──────────────────────────────
        private Rectangle   _aboutBtnRect = Rectangle.Empty;
        private Rectangle[] _navItemRects;

        // ── Drag state ────────────────────────────────────────────────
        private bool  _dragging   = false;
        private Point _dragOrigin = Point.Empty;
        private Point _formOrigin = Point.Empty;

        // ── Cached image ──────────────────────────────────────────────
        private Image _navLogo;

        // ── Child panels ──────────────────────────────────────────────
        private Panel       _titleBar;
        private Panel       _navPanel;
        private Panel       _contentPanel;
        private UserControl _currentView;

        // ── Session ───────────────────────────────────────────────────
        private OnboardingRecord _activeRecord;
        private EngineerSession  _activeSession;

        // ─────────────────────────────────────────────────────────────
        public MainShell()
        {
            SessionManager.EnsureDirectories();
            InitializeShell();
        }

        // ── WM_NCHITTEST — native resize on all edges/corners ─────────
        protected override void WndProc(ref Message m)
        {
            base.WndProc(ref m);
            if (m.Msg == WM_NCHITTEST && (int)m.Result == HTCLIENT)
            {
                var cursor = PointToClient(Cursor.Position);
                bool left   = cursor.X <= GRIP;
                bool right  = cursor.X >= ClientSize.Width  - GRIP;
                bool top    = cursor.Y <= GRIP;
                bool bottom = cursor.Y >= ClientSize.Height - GRIP;

                if (top    && left)  { m.Result = (IntPtr)HTTOPLEFT;     return; }
                if (top    && right) { m.Result = (IntPtr)HTTOPRIGHT;    return; }
                if (bottom && left)  { m.Result = (IntPtr)HTBOTTOMLEFT;  return; }
                if (bottom && right) { m.Result = (IntPtr)HTBOTTOMRIGHT; return; }
                if (left)            { m.Result = (IntPtr)HTLEFT;        return; }
                if (right)           { m.Result = (IntPtr)HTRIGHT;       return; }
                if (bottom)          { m.Result = (IntPtr)HTBOTTOM;      return; }
                // top strip handled by title bar
            }
        }

        // ── Initialization ────────────────────────────────────────────
        private void InitializeShell()
        {
            FormBorderStyle = FormBorderStyle.None;
            BackColor       = AppColors.SurfaceBase;
            ForeColor       = AppColors.TextPrimary;
            Size            = new Size(1180, 780);
            MinimumSize     = new Size(960, 640);
            StartPosition   = FormStartPosition.CenterScreen;
            Text            = "ArnotOnboardingUtility — Databranch";
            DoubleBuffered  = true;

            if (File.Exists("databranch.ico"))
                try { Icon = new Icon("databranch.ico"); } catch { }

            KeyPreview = true;
            KeyDown += (s, e) => { if (e.KeyCode == Keys.F1) ShowAboutDialog(); };

            _navItemRects = new Rectangle[4];

            // ── Add controls in DockStyle priority order ───────────────
            // Fill first → it gets whatever space is left after others claim edges
            // Left second → claims the left strip below title
            // Top LAST    → claims the top strip first (highest priority)

            _contentPanel = new Panel
            {
                Dock      = DockStyle.Fill,
                BackColor = AppColors.SurfaceBase
            };
            // Forward resize zone mouse-down events to the OS for native resize
            _contentPanel.MouseMove += (s, e) =>
            {
                var ht = GetResizeHT(_contentPanel.PointToScreen(e.Location));
                _contentPanel.Cursor = HtToCursor(ht);
            };
            _contentPanel.MouseDown += (s, e) =>
            {
                if (e.Button != MouseButtons.Left) return;
                var ht = GetResizeHT(_contentPanel.PointToScreen(e.Location));
                if (ht != HTCLIENT)
                {
                    ReleaseCapture();
                    SendMessage(Handle, WM_NCLBUTTONDOWN, (IntPtr)ht, IntPtr.Zero);
                }
            };
            _contentPanel.MouseLeave += (s, e) => _contentPanel.Cursor = Cursors.Default;
            Controls.Add(_contentPanel);

            _navPanel = new Panel
            {
                Dock      = DockStyle.Left,
                Width     = NAV_WIDTH,
                BackColor = AppColors.SurfaceRaised
            };
            _navPanel.Paint      += NavPanel_Paint;
            _navPanel.MouseMove  += NavPanel_MouseMove;
            _navPanel.MouseLeave += NavPanel_MouseLeave;
            _navPanel.MouseClick += NavPanel_MouseClick;
            _navPanel.MouseDown  += NavPanel_MouseDown;
            Controls.Add(_navPanel);

            _titleBar = new Panel
            {
                Dock      = DockStyle.Top,
                Height    = TITLE_H,
                BackColor = AppColors.SurfaceVoid
            };
            _titleBar.Paint      += TitleBar_Paint;
            _titleBar.MouseDown  += TitleBar_MouseDown;
            _titleBar.MouseMove  += TitleBar_MouseMove;
            _titleBar.MouseUp    += (s, e) => _dragging = false;
            _titleBar.MouseLeave += (s, e) =>
            {
                if (_closeHovered || _minHovered || _maxHovered)
                {
                    _closeHovered = _minHovered = _maxHovered = false;
                    _titleBar.Invalidate();
                }
            };
            Controls.Add(_titleBar); // ← LAST = highest dock priority

            FormClosing += (s, e) => _navLogo?.Dispose();
            Resize      += (s, e) => _titleBar?.Invalidate();

            ShowView(NavTarget.Landing);
        }

        // ── Title Bar ─────────────────────────────────────────────────
        private Rectangle TitleCloseRect => new Rectangle(_titleBar.Width - 46, 0, 46, TITLE_H);
        private Rectangle TitleMaxRect   => new Rectangle(_titleBar.Width - 92, 0, 46, TITLE_H);
        private Rectangle TitleMinRect   => new Rectangle(_titleBar.Width - 138, 0, 46, TITLE_H);

        private void TitleBar_Paint(object sender, PaintEventArgs e)
        {
            var g = e.Graphics;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;

            // App label
            using (var b = new SolidBrush(AppColors.TextDim))
                g.DrawString("ArnotOnboardingUtility", AppFonts.Caption, b,
                             8, (TITLE_H - AppFonts.Caption.Height) / 2);

            // Chrome buttons — filled zones
            PaintChromeBtn(g, TitleCloseRect, "✕",
                _closeHovered ? Color.FromArgb(200, AppColors.StatusError) : Color.Empty,
                _closeHovered ? AppColors.TextPrimary : AppColors.TextMuted);

            PaintChromeBtn(g, TitleMaxRect, "□",
                _maxHovered ? AppColors.SurfaceElevated : Color.Empty,
                _maxHovered ? AppColors.TextPrimary : AppColors.TextMuted);

            PaintChromeBtn(g, TitleMinRect, "−",
                _minHovered ? AppColors.SurfaceElevated : Color.Empty,
                _minHovered ? AppColors.TextPrimary : AppColors.TextMuted);
        }

        private void PaintChromeBtn(Graphics g, Rectangle r, string symbol, Color bg, Color fg)
        {
            if (bg != Color.Empty)
                using (var b = new SolidBrush(bg))
                    g.FillRectangle(b, r);

            using (var b = new SolidBrush(fg))
            {
                var fmt = new StringFormat
                {
                    Alignment     = StringAlignment.Center,
                    LineAlignment = StringAlignment.Center
                };
                g.DrawString(symbol, AppFonts.Body, b, r, fmt);
            }
        }

        private void TitleBar_MouseDown(object sender, MouseEventArgs e)
        {
            if (e.Button != MouseButtons.Left) return;
            if (TitleCloseRect.Contains(e.Location)) { Close(); return; }
            if (TitleMaxRect.Contains(e.Location))
            {
                WindowState = WindowState == FormWindowState.Maximized
                    ? FormWindowState.Normal : FormWindowState.Maximized;
                return;
            }
            if (TitleMinRect.Contains(e.Location)) { WindowState = FormWindowState.Minimized; return; }
            // Drag form
            _dragging   = true;
            _dragOrigin = Cursor.Position;
            _formOrigin = Location;
        }

        private void TitleBar_MouseMove(object sender, MouseEventArgs e)
        {
            bool oc = TitleCloseRect.Contains(e.Location);
            bool om = TitleMaxRect.Contains(e.Location);
            bool on = TitleMinRect.Contains(e.Location);
            if (oc != _closeHovered || om != _maxHovered || on != _minHovered)
            {
                _closeHovered = oc; _maxHovered = om; _minHovered = on;
                _titleBar.Invalidate();
            }
            _titleBar.Cursor = (oc || om || on) ? Cursors.Hand : Cursors.Default;

            if (_dragging && e.Button == MouseButtons.Left)
            {
                var d = new Point(Cursor.Position.X - _dragOrigin.X,
                                  Cursor.Position.Y - _dragOrigin.Y);
                Location = new Point(_formOrigin.X + d.X, _formOrigin.Y + d.Y);
            }
        }

        // ── View Switching ────────────────────────────────────────────
        private void ShowView(NavTarget target)
        {
            _activeNav = target;
            if (_currentView != null)
            {
                _contentPanel.Controls.Remove(_currentView);
                _currentView.Dispose();
                _currentView = null;
            }

            UserControl view;
            switch (target)
            {
                case NavTarget.Landing:
                    var lv = new LandingView();
                    lv.OnNewOnboardingRequested += SessionLoaded;
                    lv.OnResumeSessionRequested += SessionLoaded;
                    view = lv;
                    break;
                case NavTarget.StepRunner:
                    if (_activeRecord == null) { ShowView(NavTarget.Landing); return; }
                    var sv = new StepRunnerView(_activeRecord, _activeSession);
                    sv.OnSessionUpdated += (s, sess) => { _activeSession = sess; _navPanel.Invalidate(); };
                    view = sv;
                    break;
                case NavTarget.LogViewer:
                    view = new LogViewerView(_activeSession?.SessionLogPath);
                    break;
                case NavTarget.Settings:
                    view = new SettingsView();
                    break;
                default:
                    view = new LandingView();
                    break;
            }

            view.Dock = DockStyle.Fill;
            _contentPanel.Controls.Add(view);
            _currentView = view;
            _navPanel.Invalidate();
        }

        private void SessionLoaded(object sender, SessionLoadEventArgs e)
        {
            _activeRecord  = e.Record;
            _activeSession = e.Session;
            _sessionLoaded = true;
            ShowView(NavTarget.StepRunner);
        }

        // ── Nav Panel Paint ───────────────────────────────────────────
        private void NavPanel_Paint(object sender, PaintEventArgs e)
        {
            var g      = e.Graphics;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
            int panelW = _navPanel.Width;
            int panelH = _navPanel.Height;

            // Logo zone (same background as title bar, so they read as one unit)
            using (var b = new SolidBrush(AppColors.SurfaceVoid))
                g.FillRectangle(b, 0, 0, panelW, NAV_LOGO_H);

            // Logo image
            if (_navLogo == null && File.Exists("databranch_nav.png"))
                try { _navLogo = Image.FromFile("databranch_nav.png"); } catch { }

            int imgSize = 48;
            int imgX    = 14;
            int imgY    = (NAV_LOGO_H - imgSize) / 2;
            if (_navLogo != null)
                g.DrawImage(_navLogo, imgX, imgY, imgSize, imgSize);

            int tx = imgX + imgSize + 10;
            using (var b = new SolidBrush(AppColors.BrandRedSoft))
                g.DrawString("DATABRANCH", AppFonts.NavEyebrow, b, tx, 20);
            using (var b = new SolidBrush(AppColors.TextPrimary))
                g.DrawString("Onboarding\nUtility", AppFonts.NavTitle, b, tx, 36);
            var ver = Assembly.GetExecutingAssembly().GetName().Version;
            using (var b = new SolidBrush(AppColors.TextDim))
                g.DrawString($"v{ver.Major}.{ver.Minor}.{ver.Build}.{ver.Revision}",
                             AppFonts.NavVersion, b, tx, 74);

            using (var pen = new Pen(AppColors.BorderSubtle))
                g.DrawLine(pen, 0, NAV_LOGO_H, panelW, NAV_LOGO_H);

            int y = NAV_LOGO_H + 8;
            DrawNavSection(g, "WORKFLOW", ref y, panelW);
            DrawNavItem(g, NavTarget.Landing,    "  Home",               ref y, panelW, 0);
            DrawNavItem(g, NavTarget.StepRunner, "  Current Onboarding", ref y, panelW, 1);
            DrawNavSection(g, "SESSION", ref y, panelW);
            DrawNavItem(g, NavTarget.LogViewer,  "  View Log",           ref y, panelW, 2);
            DrawNavItem(g, NavTarget.Settings,   "  Settings",           ref y, panelW, 3);

            // Footer
            int footerY = panelH - FOOTER_H;
            using (var pen = new Pen(AppColors.BorderSubtle))
                g.DrawLine(pen, 0, footerY, panelW, footerY);
            using (var b = new SolidBrush(AppColors.SurfaceVoid))
                g.FillRectangle(b, 0, footerY, panelW, FOOTER_H);

            string ft = _sessionLoaded && _activeSession != null
                ? _activeSession.EmployeeName : "No session loaded";
            using (var b = new SolidBrush(AppColors.TextMuted))
                g.DrawString(ft, AppFonts.Caption, b, 14, footerY + 14);

            // About (?) button
            int aS = 24, aX = panelW - aS - 12, aY = footerY + (FOOTER_H - aS) / 2;
            _aboutBtnRect = new Rectangle(aX, aY, aS, aS);
            using (var b = new SolidBrush(_aboutHovered ? AppColors.SurfaceElevated : AppColors.SurfaceCard))
                g.FillEllipse(b, _aboutBtnRect);
            using (var pen = new Pen(AppColors.BorderMid))
                g.DrawEllipse(pen, _aboutBtnRect);
            var fmt2 = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
            using (var b = new SolidBrush(AppColors.TextMuted))
                g.DrawString("?", AppFonts.LabelBold, b, _aboutBtnRect, fmt2);
        }

        private void DrawNavSection(Graphics g, string label, ref int y, int w)
        {
            using (var b = new SolidBrush(AppColors.TextDim))
                g.DrawString(label, AppFonts.NavSection, b, 16, y + 7);
            y += NAV_SECTION_H;
        }

        private void DrawNavItem(Graphics g, NavTarget target, string text,
                                 ref int y, int panelW, int idx)
        {
            bool isActive   = _activeNav == target;
            bool isDisabled = (target == NavTarget.StepRunner || target == NavTarget.LogViewer)
                              && !_sessionLoaded;

            var r = new Rectangle(0, y, panelW, NAV_ITEM_H);
            _navItemRects[idx] = r;

            if (isActive)
            {
                using (var b = new SolidBrush(AppColors.SurfaceCard))
                    g.FillRectangle(b, r);
                using (var b = new SolidBrush(AppColors.BrandRedSoft))
                    g.FillRectangle(b, 0, y, 3, NAV_ITEM_H);
            }

            Color tc = isDisabled ? AppColors.TextDim : isActive ? AppColors.TextPrimary : AppColors.TextMuted;
            var font = isActive ? AppFonts.NavItemBold : AppFonts.NavItem;
            using (var b = new SolidBrush(tc))
                g.DrawString(text, font, b, 18, y + (NAV_ITEM_H - font.Height) / 2);
            y += NAV_ITEM_H;
        }

        // ── Nav Mouse ─────────────────────────────────────────────────
        private void NavPanel_MouseMove(object sender, MouseEventArgs e)
        {
            bool oa = !_aboutBtnRect.IsEmpty && _aboutBtnRect.Contains(e.Location);
            if (oa != _aboutHovered) { _aboutHovered = oa; _navPanel.Invalidate(_aboutBtnRect); }
            bool overItem = false;
            foreach (var r in _navItemRects) if (!r.IsEmpty && r.Contains(e.Location)) { overItem = true; break; }
            _navPanel.Cursor = (oa || overItem) ? Cursors.Hand : Cursors.Default;
        }

        private void NavPanel_MouseLeave(object sender, EventArgs e)
        {
            if (_aboutHovered) { _aboutHovered = false; _navPanel.Invalidate(_aboutBtnRect); }
            _navPanel.Cursor = Cursors.Default;
        }

        private void NavPanel_MouseClick(object sender, MouseEventArgs e)
        {
            if (_aboutBtnRect.Contains(e.Location)) { ShowAboutDialog(); return; }
            var targets = new[] { NavTarget.Landing, NavTarget.StepRunner, NavTarget.LogViewer, NavTarget.Settings };
            for (int i = 0; i < _navItemRects.Length; i++)
            {
                if (_navItemRects[i].Contains(e.Location))
                {
                    var t = targets[i];
                    if ((t == NavTarget.StepRunner || t == NavTarget.LogViewer) && !_sessionLoaded) return;
                    ShowView(t);
                    return;
                }
            }
        }

        private void NavPanel_MouseDown(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Left && e.Y < NAV_LOGO_H)
            {
                _dragging   = true;
                _dragOrigin = Cursor.Position;
                _formOrigin = Location;
            }
        }

        // ── About Dialog ──────────────────────────────────────────────
        private void ShowAboutDialog()
        {
            var ver = Assembly.GetExecutingAssembly().GetName().Version;
            using (var dlg = new Form())
            {
                dlg.FormBorderStyle = FormBorderStyle.None;
                dlg.BackColor       = AppColors.SurfaceCard;
                dlg.Size            = new Size(480, 300);
                dlg.StartPosition   = FormStartPosition.CenterParent;
                dlg.KeyPreview      = true;
                dlg.KeyDown += (s, e) => { if (e.KeyCode == Keys.Escape) dlg.Close(); };

                var hdr = new Panel { Dock = DockStyle.Top, Height = 52, BackColor = AppColors.SurfaceVoid };
                hdr.Paint += (s, e2) =>
                {
                    using (var b = new SolidBrush(AppColors.BrandRedSoft))
                        e2.Graphics.DrawString("DATABRANCH", AppFonts.NavEyebrow, b, 18, 8);
                    using (var b = new SolidBrush(AppColors.TextPrimary))
                        e2.Graphics.DrawString("ArnotOnboardingUtility", AppFonts.Heading3, b, 18, 24);
                };
                dlg.Controls.Add(hdr);

                var body = new Panel { Dock = DockStyle.Fill, BackColor = AppColors.SurfaceCard, Padding = new Padding(18, 14, 18, 14) };
                dlg.Controls.Add(body);

                int y = 0;
                void Row(string text, Font font, Color color, int indent = 0)
                {
                    body.Controls.Add(new Label { Text = text, Font = font, ForeColor = color, BackColor = Color.Transparent, Bounds = new Rectangle(indent, y, 440, 20), AutoEllipsis = true });
                    y += 22;
                }

                Row($"v{ver.Major}.{ver.Minor}.{ver.Build}.{ver.Revision}", AppFonts.Mono, AppColors.BrandBlue);
                Row("Engineer IT Onboarding Workflow Utility", AppFonts.BodySmall, AppColors.TextSecondary);
                Row("Arnot Realty Corporation — Powered by Databranch", AppFonts.BodySmall, AppColors.TextMuted);
                y += 6;
                body.Controls.Add(new Panel { Bounds = new Rectangle(0, y, 440, 1), BackColor = AppColors.BorderSubtle });
                y += 10;
                Row("VERSION HISTORY", AppFonts.NavSection, AppColors.TextDim);
                Row("v1.0.0.0  2026-02-28  Milestone 1: Shell, landing, session infrastructure", AppFonts.MonoSmall, AppColors.TextMuted);
                Row("v1.0.1.0  2026-02-28  Fix: dock order, title bar, panel layout", AppFonts.MonoSmall, AppColors.TextMuted);
                Row("v1.0.2.0  2026-02-28  Fix: native resize, content clip, nav alignment", AppFonts.MonoSmall, AppColors.TextMuted);

                var btnClose = new Button { Text = "Close", Bounds = new Rectangle(352, y + 8, 88, 28), DialogResult = DialogResult.OK };
                ThemeHelper.StyleAsGhostButton(btnClose);
                body.Controls.Add(btnClose);

                dlg.Paint += (s, e2) => { using (var pen = new Pen(AppColors.BorderDefault)) e2.Graphics.DrawRectangle(pen, 0, 0, dlg.Width - 1, dlg.Height - 1); };
                dlg.ShowDialog(this);
            }
        }
    }

    // ── Shared Event Args ─────────────────────────────────────────────
    public class SessionLoadEventArgs : EventArgs
    {
        public OnboardingRecord Record  { get; }
        public EngineerSession  Session { get; }
        public SessionLoadEventArgs(OnboardingRecord record, EngineerSession session)
        { Record = record; Session = session; }
    }
}
