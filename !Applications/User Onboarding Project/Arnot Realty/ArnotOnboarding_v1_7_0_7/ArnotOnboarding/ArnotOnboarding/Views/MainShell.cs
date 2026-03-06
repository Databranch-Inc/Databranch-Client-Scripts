// =============================================================
// ArnotOnboarding — MainShell.cs
// Version    : 1.6.0.0
// Author     : Sam Kirsch
// Company    : Databranch
// Created    : 2026-02-22
// Modified   : 2026-02-28
// Description: Top-level application window. Contains the custom-painted
//              dark navigation rail on the left and a content host panel
//              on the right. Manages view switching and window state
//              persistence. All major views are loaded into this shell.
//
// v1.4.0.0 — Added locked-record warning banner in the nav footer.
//             When one or more In Progress drafts have an active
//             network lock (i.e. were created via Restart Onboarding),
//             a yellow warning box is drawn above the "Signed in as"
//             footer line:
//               "⚠ You are currently editing [one / two / ...] completed
//                onboarding(s) and have not exported it/them.
//                This/These file(s) is/are locked for other users."
//             The banner count updates on every nav repaint so it
//             reflects the live state of the draft index.
//
// v1.5.0.0 — AboutDialog wired to logo/version header click and F1.
//             Version string in nav updated to v1.7.0.0.
//             Nav hint text: "v1.7.0.0".
//
// v1.6.0.0 — Databranch logo PNG drawn in nav header beside text.
//             About (?) circle button in footer row (right side, opposite
//             Signed in as). Logo-area click no longer opens About.
//             this.Icon set from databranch.ico (title bar + taskbar).
//             ApplicationIcon in .csproj sets EXE icon.
//             _navLogo disposed on FormClosing.
//             FormClosing now also releases all locks held by this
//             session for orphaned drafts (safety net).
// =============================================================

using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;
using ArnotOnboarding.Managers;
using ArnotOnboarding.Theme;
using ArnotOnboarding.Views;

namespace ArnotOnboarding.Views
{
    public partial class MainShell : Form
    {
        // ── State ────────────────────────────────────────────────────
        private UserControl _activeView;
        private NavItem     _activeNavItem;

        // ── Nav item definitions ─────────────────────────────────────
        private readonly List<NavItem> _navItems = new List<NavItem>();

        // ── Child views (lazy-loaded) ────────────────────────────────
        private DashboardView      _dashboardView;
        private DraftListView      _draftListView;
        private RecordLibraryView  _recordLibraryView;
        private RequestorView      _requestorView;
        private SettingsView       _settingsView;

        // ── Nav panel geometry ───────────────────────────────────────
        private const int NAV_WIDTH           = 220;
        private const int NAV_LOGO_HEIGHT     = 90;
        private const int NAV_ITEM_HEIGHT     = 44;
        private const int NAV_ITEM_INDENT     = 16;

        // Lock warning banner height (0 when no locked drafts exist)
        private const int LOCK_BANNER_HEIGHT  = 66;
        // "Signed in as" footer height
        private const int USER_FOOTER_HEIGHT  = 50;

        public MainShell()
        {
            InitializeComponent();
            SetupWindow();
            BuildNavItems();
            RestoreWindowState();
        }

        // ── Window Setup ─────────────────────────────────────────────

        private void SetupWindow()
        {
            this.Text            = "Arnot Realty — IT Onboarding Request";
            this.BackColor       = AppColors.SurfaceBase;
            this.ForeColor       = AppColors.TextSecondary;
            this.Font            = AppFonts.Body;
            this.MinimumSize     = new Size(900, 620);
            this.StartPosition   = FormStartPosition.Manual;
            this.KeyPreview      = true;
            this.KeyDown        += (s, e) =>
            {
                if (e.KeyCode == Keys.F1)
                {
                    e.Handled = true;
                    ShowAboutDialog();
                }
            };

            // Set window / taskbar icon from the ICO file next to the EXE.
            // Wrapped in try/catch — missing ICO is non-fatal during dev.
            try
            {
                string exeDir  = System.IO.Path.GetDirectoryName(
                    System.Reflection.Assembly.GetExecutingAssembly().Location);
                string icoPath = System.IO.Path.Combine(exeDir, "databranch.ico");
                if (System.IO.File.Exists(icoPath))
                    this.Icon = new System.Drawing.Icon(icoPath);
            }
            catch { /* non-fatal */ }
        }

        private void RestoreWindowState()
        {
            var s = AppSettingsManager.Instance.Settings;
            this.Location = new Point(s.WindowX, s.WindowY);
            this.Size     = new Size(s.WindowWidth, s.WindowHeight);
            if (s.WindowMaximized)
                this.WindowState = FormWindowState.Maximized;
        }

        // ── Nav Item Definitions ─────────────────────────────────────

        private void BuildNavItems()
        {
            _navItems.AddRange(new[]
            {
                new NavItem { Id = "new",      Icon = "+",  Label = "New Onboarding",   Action = () => ShowView(GetDashboardView()) },
                new NavItem { Id = "drafts",   Icon = "≡",  Label = "In Progress",      Action = () => ShowView(GetDraftListView()), BadgeValue = GetDraftCount },
                new NavItem { Id = "records",  Icon = "⊞",  Label = "Past Records",     Action = () => ShowView(GetRecordLibraryView(forceRefresh: true)) },
                new NavItem { Separator = true },
                new NavItem { Id = "requestor",Icon = "◉",  Label = "My Information",   Action = () => ShowView(GetRequestorView()) },
                new NavItem { Id = "settings", Icon = "⚙",  Label = "Settings",         Action = () => ShowView(GetSettingsView()) },
            });
        }

        private int GetDraftCount()
        {
            try { return new DraftManager(AppSettingsManager.Instance).GetAllDrafts().Count; }
            catch { return 0; }
        }

        // ── Lock banner data ─────────────────────────────────────────

        /// <summary>
        /// Returns the number of In Progress drafts that currently hold a network lock
        /// (i.e. were created via Restart Onboarding and have not yet been finalized).
        /// Called during nav repaint so the banner is always current.
        /// </summary>
        private int GetLockedDraftCount()
        {
            try { return new DraftManager(AppSettingsManager.Instance).GetLockedDrafts().Count; }
            catch { return 0; }
        }

        // ── View Lazy Loaders ────────────────────────────────────────

        private UserControl GetDashboardView()
        {
            if (_dashboardView == null || _dashboardView.IsDisposed)
                _dashboardView = new DashboardView();
            return _dashboardView;
        }

        private UserControl GetDraftListView()
        {
            if (_draftListView == null || _draftListView.IsDisposed)
                _draftListView = new DraftListView();
            else
                _draftListView.LoadDrafts();
            return _draftListView;
        }

        private UserControl GetRecordLibraryView(bool forceRefresh = false)
        {
            if (forceRefresh || _recordLibraryView == null || _recordLibraryView.IsDisposed)
            {
                if (_recordLibraryView != null && !_recordLibraryView.IsDisposed)
                    _recordLibraryView.Dispose();
                _recordLibraryView = new RecordLibraryView();
            }
            return _recordLibraryView;
        }

        private UserControl GetRequestorView()
        {
            if (_requestorView == null || _requestorView.IsDisposed)
                _requestorView = new RequestorView();
            return _requestorView;
        }

        private UserControl GetSettingsView()
        {
            if (_settingsView == null || _settingsView.IsDisposed)
                _settingsView = new SettingsView();
            return _settingsView;
        }

        // ── View Switching ────────────────────────────────────────────

        public void ShowView(UserControl view, NavItem navItem = null)
        {
            if (_activeView != null)
                _contentPanel.Controls.Remove(_activeView);

            _activeView = view;
            view.Dock = DockStyle.Fill;
            _contentPanel.Controls.Add(view);
            view.BringToFront();

            if (navItem != null)
            {
                _activeNavItem = navItem;
                _navPanel.Invalidate();
            }
        }

        public void NavigateTo(string navId)
        {
            var item = _navItems.Find(n => n.Id == navId);
            if (item != null)
            {
                _activeNavItem = item;
                item.Action?.Invoke();
                _navPanel.Invalidate();
            }
        }

        // ── Nav Panel Custom Painting ────────────────────────────────

        // Cached logo image — loaded once, reused on every paint
        private Image _navLogo;
        // Hit rect for the ⓘ About button in the footer
        private Rectangle _aboutBtnRect = Rectangle.Empty;

        private Image GetNavLogo()
        {
            if (_navLogo != null) return _navLogo;
            try
            {
                string exeDir = System.IO.Path.GetDirectoryName(
                    System.Reflection.Assembly.GetExecutingAssembly().Location);
                string path = System.IO.Path.Combine(exeDir, "databranch_nav.png");
                if (System.IO.File.Exists(path))
                    _navLogo = Image.FromFile(path);
            }
            catch { /* logo optional — missing file is non-fatal */ }
            return _navLogo;
        }

        private void navPanel_Paint(object sender, PaintEventArgs e)
        {
            var g = e.Graphics;
            g.SmoothingMode      = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            g.TextRenderingHint  = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;

            int panelWidth = _navPanel.Width;

            // ── Logo/Title Area ───────────────────────────────────────
            // RULE: AppFonts static fields must NEVER be in using() blocks.
            // They are shared instances — disposing them corrupts all subsequent draws.
            // Only objects created with 'new' go in using() blocks.

            using (var logoBg = new SolidBrush(AppColors.SurfaceVoid))
                g.FillRectangle(logoBg, 0, 0, panelWidth, NAV_LOGO_HEIGHT);

            using (var accentBar = new SolidBrush(AppColors.BrandRedSoft))
                g.FillRectangle(accentBar, 0, 0, 3, NAV_LOGO_HEIGHT);

            // Logo image (56×56, vertically centred in the 90px header)
            int logoSize    = 56;
            int logoX       = 8;
            int logoY       = (NAV_LOGO_HEIGHT - logoSize) / 2;
            var logo        = GetNavLogo();
            if (logo != null)
                g.DrawImage(logo, logoX, logoY, logoSize, logoSize);

            // Text block sits to the right of the logo
            int textX = logoX + logoSize + 8;
            using (var eyebrowBrush = new SolidBrush(AppColors.BrandRedSoft))
                g.DrawString("DATABRANCH", AppFonts.EyebrowLabel, eyebrowBrush, textX, 18);

            using (var titleBrush = new SolidBrush(AppColors.TextPrimary))
                g.DrawString("Arnot Onboarding", AppFonts.Heading3, titleBrush, textX, 38);

            using (var verBrush = new SolidBrush(AppColors.TextDim))
                g.DrawString("v1.7.0.0", AppFonts.Version, verBrush, textX, 66);

            using (var divPen = new Pen(AppColors.BorderSubtle))
                g.DrawLine(divPen, 0, NAV_LOGO_HEIGHT - 1, panelWidth, NAV_LOGO_HEIGHT - 1);

            // ── Nav Items ─────────────────────────────────────────────
            int yOffset = NAV_LOGO_HEIGHT + 8;

            foreach (var item in _navItems)
            {
                // Separator
                if (item.Separator)
                {
                    using (var sepPen = new Pen(AppColors.BorderSubtle))
                        g.DrawLine(sepPen, NAV_ITEM_INDENT, yOffset + 8, panelWidth - NAV_ITEM_INDENT, yOffset + 8);
                    yOffset += 24;
                    continue;
                }

                bool isActive = (_activeNavItem != null && _activeNavItem.Id == item.Id);
                Rectangle itemRect = new Rectangle(0, yOffset, panelWidth, NAV_ITEM_HEIGHT);

                if (isActive)
                {
                    using (var activeBg = new SolidBrush(AppColors.SurfaceCard))
                        g.FillRectangle(activeBg, itemRect);
                    using (var indicator = new SolidBrush(AppColors.BrandRedSoft))
                        g.FillRectangle(indicator, 0, yOffset, 3, NAV_ITEM_HEIGHT);
                }

                using (var iconFont = new Font("Segoe UI Symbol", 12f, FontStyle.Regular, GraphicsUnit.Point))
                using (var iconBrush = new SolidBrush(isActive ? AppColors.BrandRedSoft : AppColors.TextMuted))
                {
                    g.DrawString(item.Icon, iconFont, iconBrush,
                        (float)(NAV_ITEM_INDENT + 4),
                        (float)(yOffset + (NAV_ITEM_HEIGHT - 18) / 2));
                }

                Font labelFont = isActive ? AppFonts.NavItemActive : AppFonts.NavItem;
                using (var labelBrush = new SolidBrush(isActive ? AppColors.TextPrimary : AppColors.TextMuted))
                {
                    g.DrawString(item.Label, labelFont, labelBrush,
                        (float)(NAV_ITEM_INDENT + 30),
                        (float)(yOffset + (NAV_ITEM_HEIGHT - 16) / 2));
                }

                // Badge (draft count, etc.)
                if (item.BadgeValue != null)
                {
                    int count = item.BadgeValue();
                    if (count > 0)
                    {
                        string badgeText = count.ToString();
                        SizeF  badgeSize = g.MeasureString(badgeText, AppFonts.MonoSmall);
                        int    badgeW    = Math.Max((int)badgeSize.Width + 10, 22);
                        int    badgeH    = 18;
                        int    badgeX    = panelWidth - badgeW - 10;
                        int    badgeY    = yOffset + (NAV_ITEM_HEIGHT - badgeH) / 2;

                        using (var badgeBg = new SolidBrush(AppColors.BrandRedMuted))
                            g.FillRectangle(badgeBg, badgeX, badgeY, badgeW, badgeH);

                        using (var badgeFg = new SolidBrush(AppColors.TextPrimary))
                            g.DrawString(badgeText, AppFonts.MonoSmall, badgeFg,
                                (float)(badgeX + (badgeW - badgeSize.Width) / 2),
                                (float)(badgeY + (badgeH - badgeSize.Height) / 2));
                    }
                }

                item.HitRect = itemRect;
                yOffset += NAV_ITEM_HEIGHT;
            }

            // ── Bottom section: lock warning banner + user footer ─────
            // Layout from the bottom up:
            //   [USER_FOOTER_HEIGHT]  — "Signed in as" block
            //   [LOCK_BANNER_HEIGHT]  — warning box (only when locked drafts > 0)
            //   [1px divider line]

            int lockedCount = GetLockedDraftCount();

            // Total bottom block height
            int bottomBlockH = USER_FOOTER_HEIGHT + (lockedCount > 0 ? LOCK_BANNER_HEIGHT : 0);
            int dividerY     = _navPanel.Height - bottomBlockH;

            // Divider line
            using (var divPen = new Pen(AppColors.BorderSubtle))
                g.DrawLine(divPen, 0, dividerY, panelWidth, dividerY);

            // ── Lock warning banner (drawn between divider and footer) ─
            if (lockedCount > 0)
            {
                int bannerY = dividerY + 1;
                int bannerH = LOCK_BANNER_HEIGHT - 1;

                // Warning background
                using (var warnBg = new SolidBrush(Color.FromArgb(30, 25, 0)))
                    g.FillRectangle(warnBg, 0, bannerY, panelWidth, bannerH);

                // Left accent stripe in warning amber
                using (var warnBar = new SolidBrush(AppColors.StatusWarn))
                    g.FillRectangle(warnBar, 0, bannerY, 3, bannerH);

                // Build the message text
                string countWord  = NumberToWord(lockedCount);
                string plural     = lockedCount == 1 ? "" : "s";
                string itThem     = lockedCount == 1 ? "it" : "them";
                string thisThese  = lockedCount == 1 ? "This file is" : "These files are";

                string line1 = $"⚠  Editing {countWord} completed onboarding{plural}";
                string line2 = $"   not yet exported — {thisThese}";
                string line3 = $"   locked for other users.";

                float bannerTextX = NAV_ITEM_INDENT + 4;
                float lineH       = 16f;

                using (var warnFg = new SolidBrush(AppColors.StatusWarn))
                {
                    g.DrawString(line1, AppFonts.BodySmall, warnFg, bannerTextX, bannerY + 8);
                    g.DrawString(line2, AppFonts.Caption,   warnFg, bannerTextX, bannerY + 8 + lineH + 2);
                    g.DrawString(line3, AppFonts.Caption,   warnFg, bannerTextX, bannerY + 8 + lineH * 2 + 4);
                }
            }

            // ── "Signed in as" footer ─────────────────────────────────
            int footerY = _navPanel.Height - USER_FOOTER_HEIGHT;

            string userName = AppSettingsManager.Instance.Requestor?.Name;

            if (!string.IsNullOrWhiteSpace(userName))
            {
                using (var dimBrush = new SolidBrush(AppColors.TextDim))
                    g.DrawString("Signed in as", AppFonts.Caption, dimBrush, NAV_ITEM_INDENT, footerY + 8);
                using (var mutedBrush = new SolidBrush(AppColors.TextMuted))
                    g.DrawString(userName, AppFonts.LabelBold, mutedBrush, NAV_ITEM_INDENT, footerY + 24);
            }
            else
            {
                using (var dimBrush = new SolidBrush(AppColors.TextDim))
                    g.DrawString("Set up your profile →", AppFonts.Caption, dimBrush, NAV_ITEM_INDENT, footerY + 16);
            }

            // ── About (?) button — right side of footer ───────────────
            // Circle with ? drawn on the right edge of the footer row.
            // Hit rect stored for click detection.
            int btnDiam = 24;
            int btnX    = panelWidth - btnDiam - 12;
            int btnY    = footerY + (USER_FOOTER_HEIGHT - btnDiam) / 2;
            _aboutBtnRect = new Rectangle(btnX, btnY, btnDiam, btnDiam);

            bool hoverAbout = _aboutBtnHovered;

            using (var circleBg = new SolidBrush(hoverAbout ? AppColors.SurfaceHigh : AppColors.SurfaceElevated))
            using (var circlePen = new Pen(hoverAbout ? AppColors.BrandBlue : AppColors.BorderMid))
            {
                g.FillEllipse(circleBg, btnX, btnY, btnDiam, btnDiam);
                g.DrawEllipse(circlePen, btnX, btnY, btnDiam, btnDiam);
            }
            using (var qBrush = new SolidBrush(hoverAbout ? AppColors.BrandBlue : AppColors.TextMuted))
            using (var qFont = new Font("Segoe UI", 11f, FontStyle.Bold, GraphicsUnit.Point))
            {
                string q = "?";
                SizeF  qSize = g.MeasureString(q, qFont);
                g.DrawString(q, qFont, qBrush,
                    btnX + (btnDiam - qSize.Width)  / 2f,
                    btnY + (btnDiam - qSize.Height) / 2f);
            }
        }

        // ── Nav Mouse Hit Detection ───────────────────────────────────

        private void navPanel_MouseClick(object sender, MouseEventArgs e)
        {
            // About (?) button in the footer
            if (!_aboutBtnRect.IsEmpty && _aboutBtnRect.Contains(e.Location))
            {
                ShowAboutDialog();
                return;
            }

            // Logo header area is no longer an About trigger — just pass through
            if (e.Y < NAV_LOGO_HEIGHT) return;

            foreach (var item in _navItems)
            {
                if (item.Separator || item.HitRect.IsEmpty) continue;
                if (item.HitRect.Contains(e.Location))
                {
                    _activeNavItem = item;
                    item.Action?.Invoke();
                    _navPanel.Invalidate();
                    break;
                }
            }
        }

        private bool _aboutBtnHovered = false;

        private void navPanel_MouseMove(object sender, MouseEventArgs e)
        {
            bool overAbout = !_aboutBtnRect.IsEmpty && _aboutBtnRect.Contains(e.Location);
            bool overItem  = overAbout;

            if (!overItem && e.Y >= NAV_LOGO_HEIGHT)
            {
                foreach (var item in _navItems)
                {
                    if (!item.Separator && item.HitRect.Contains(e.Location))
                    {
                        overItem = true;
                        break;
                    }
                }
            }

            _navPanel.Cursor = overItem ? Cursors.Hand : Cursors.Default;

            // Only repaint when the About button hover state actually changes —
            // invalidating on every MouseMove causes the entire nav to flicker.
            if (overAbout != _aboutBtnHovered)
            {
                _aboutBtnHovered = overAbout;
                _navPanel.Invalidate(_aboutBtnRect); // invalidate only the button area
            }
        }

        private void navPanel_MouseLeave(object sender, EventArgs e)
        {
            if (_aboutBtnHovered)
            {
                _aboutBtnHovered = false;
                _navPanel.Invalidate(_aboutBtnRect);
            }
            _navPanel.Cursor = Cursors.Default;
        }

        private void ShowAboutDialog()
        {
            using (var dlg = new AboutDialog())
                dlg.ShowDialog(this);
        }

        // ── Form Closing — Save State & Release Locks ─────────────────

        private void MainShell_FormClosing(object sender, FormClosingEventArgs e)
        {
            var s = AppSettingsManager.Instance.Settings;

            if (this.WindowState == FormWindowState.Maximized)
                s.WindowMaximized = true;
            else
            {
                s.WindowMaximized = false;
                s.WindowX         = this.Location.X;
                s.WindowY         = this.Location.Y;
                s.WindowWidth     = this.Size.Width;
                s.WindowHeight    = this.Size.Height;
            }

            AppSettingsManager.Instance.SaveSettings();

            // Dispose cached logo image
            _navLogo?.Dispose();
            _navLogo = null;

            // Safety net: release any network locks held by this session.
            // Normally locks are released on Finalize or draft Delete.
            // This catches the case where the app is closed while a restarted
            // draft is still in progress (lock would otherwise be stuck until stale).
            try
            {
                var dm      = new DraftManager(AppSettingsManager.Instance);
                var locked  = dm.GetLockedDrafts();
                foreach (var draft in locked)
                {
                    if (!string.IsNullOrEmpty(draft.SourceJsonPath))
                        LockManager.Release(draft.SourceJsonPath);
                }
            }
            catch { /* Do not block close on lock cleanup failure */ }
        }

        // ── Form Load — Default View ──────────────────────────────────

        private void MainShell_Load(object sender, EventArgs e)
        {
            _activeNavItem = _navItems.Find(n => n.Id == "new");
            var dashboard = GetDashboardView() as DashboardView;
            ShowView(dashboard, _activeNavItem);
            _navPanel.Invalidate();
            dashboard.CheckForDrafts();
        }

        // ── Public Navigation Helpers ─────────────────────────────────

        public void RefreshNav()
        {
            _navPanel.Invalidate();
        }

        public void ShowWizard(WizardView wizard)
        {
            _activeNavItem = _navItems.Find(n => n.Id == "new");
            ShowView(wizard, _activeNavItem);
            _navPanel.Invalidate();
        }

        // ── Utility ──────────────────────────────────────────────────

        /// <summary>
        /// Converts small integers to lowercase English words for the warning banner.
        /// Falls back to the numeric string for values outside the lookup range.
        /// </summary>
        private static string NumberToWord(int n)
        {
            switch (n)
            {
                case 1:  return "one";
                case 2:  return "two";
                case 3:  return "three";
                case 4:  return "four";
                case 5:  return "five";
                case 6:  return "six";
                case 7:  return "seven";
                case 8:  return "eight";
                case 9:  return "nine";
                case 10: return "ten";
                default: return n.ToString();
            }
        }
    }

    // ── NavItem helper class ──────────────────────────────────────────

    public class NavItem
    {
        public string    Id         { get; set; }
        public string    Icon       { get; set; }
        public string    Label      { get; set; }
        public Action    Action     { get; set; }
        public bool      Separator  { get; set; }
        public Func<int> BadgeValue { get; set; }
        public Rectangle HitRect    { get; set; }
    }
}
