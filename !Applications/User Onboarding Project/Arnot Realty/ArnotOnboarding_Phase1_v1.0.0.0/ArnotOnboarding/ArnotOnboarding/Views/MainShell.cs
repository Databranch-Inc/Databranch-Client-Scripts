// =============================================================
// ArnotOnboarding — MainShell.cs
// Version    : 1.0.0.0
// Author     : Sam Kirsch
// Company    : Databranch
// Created    : 2026-02-22
// Modified   : 2026-02-22
// Description: Top-level application window. Contains the custom-painted
//              dark navigation rail on the left and a content host panel
//              on the right. Manages view switching and window state
//              persistence. All major views are loaded into this shell.
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
        private const int NAV_WIDTH       = 220;
        private const int NAV_LOGO_HEIGHT = 90;
        private const int NAV_ITEM_HEIGHT = 44;
        private const int NAV_ITEM_INDENT = 16;

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
                new NavItem { Id = "records",  Icon = "⊞",  Label = "Past Records",     Action = () => ShowView(GetRecordLibraryView()) },
                new NavItem { Separator = true },
                new NavItem { Id = "requestor",Icon = "◉",  Label = "My Information",   Action = () => ShowView(GetRequestorView()) },
                new NavItem { Id = "settings", Icon = "⚙",  Label = "Settings",         Action = () => ShowView(GetSettingsView()) },
            });
        }

        private int GetDraftCount()
        {
            try
            {
                return new DraftManager(AppSettingsManager.Instance).GetAllDrafts().Count;
            }
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
            return _draftListView;
        }

        private UserControl GetRecordLibraryView()
        {
            if (_recordLibraryView == null || _recordLibraryView.IsDisposed)
                _recordLibraryView = new RecordLibraryView();
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

        /// <summary>
        /// Removes the current view and loads the new one into the content panel.
        /// </summary>
        public void ShowView(UserControl view, NavItem navItem = null)
        {
            if (_activeView != null)
            {
                _contentPanel.Controls.Remove(_activeView);
            }

            _activeView = view;
            view.Dock = DockStyle.Fill;
            _contentPanel.Controls.Add(view);
            view.BringToFront();

            // Update active nav state
            if (navItem != null)
            {
                _activeNavItem = navItem;
                _navPanel.Invalidate(); // Trigger repaint for active indicator
            }
        }

        /// <summary>Public entry point for navigating to a view by nav ID from child views.</summary>
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

        private void navPanel_Paint(object sender, PaintEventArgs e)
        {
            var g = e.Graphics;
            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;

            int panelWidth = _navPanel.Width;

            // ── Logo/Title Area ───────────────────────────────────────
            using (var logoBg = new SolidBrush(AppColors.SurfaceVoid))
                g.FillRectangle(logoBg, 0, 0, panelWidth, NAV_LOGO_HEIGHT);

            // Red accent bar at top
            using (var accentBar = new SolidBrush(AppColors.BrandRedSoft))
                g.FillRectangle(accentBar, 0, 0, 3, NAV_LOGO_HEIGHT);

            // Company eyebrow
            using (var eyebrowFont = AppFonts.EyebrowLabel)
            using (var eyebrowBrush = new SolidBrush(AppColors.BrandRedSoft))
                g.DrawString("DATABRANCH", eyebrowFont, eyebrowBrush, NAV_ITEM_INDENT + 4, 18);

            // App title
            using (var titleFont = AppFonts.Heading3)
            using (var titleBrush = new SolidBrush(AppColors.TextPrimary))
                g.DrawString("Arnot Onboarding", titleFont, titleBrush, NAV_ITEM_INDENT + 4, 38);

            // Version
            using (var verFont = AppFonts.Version)
            using (var verBrush = new SolidBrush(AppColors.TextDim))
                g.DrawString("v1.0.0.0", verFont, verBrush, NAV_ITEM_INDENT + 4, 66);

            // Divider below logo
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

                bool isActive = (_activeNavItem?.Id == item.Id);
                Rectangle itemRect = new Rectangle(0, yOffset, panelWidth, NAV_ITEM_HEIGHT);

                // Active or hover background
                if (isActive)
                {
                    using (var activeBg = new SolidBrush(AppColors.SurfaceCard))
                        g.FillRectangle(activeBg, itemRect);

                    // Red left indicator bar
                    using (var indicator = new SolidBrush(AppColors.BrandRedSoft))
                        g.FillRectangle(indicator, 0, yOffset, 3, NAV_ITEM_HEIGHT);
                }

                // Icon
                using (var iconFont = new Font("Segoe UI Symbol", 12f))
                using (var iconBrush = new SolidBrush(isActive ? AppColors.BrandRedSoft : AppColors.TextMuted))
                {
                    g.DrawString(item.Icon, iconFont, iconBrush,
                        NAV_ITEM_INDENT + 4, yOffset + (NAV_ITEM_HEIGHT - 18) / 2);
                }

                // Label
                using (var labelFont = isActive ? AppFonts.NavItemActive : AppFonts.NavItem)
                using (var labelBrush = new SolidBrush(isActive ? AppColors.TextPrimary : AppColors.TextMuted))
                {
                    g.DrawString(item.Label, labelFont, labelBrush,
                        NAV_ITEM_INDENT + 30, yOffset + (NAV_ITEM_HEIGHT - 16) / 2);
                }

                // Badge (e.g. draft count)
                if (item.BadgeValue != null)
                {
                    int count = item.BadgeValue();
                    if (count > 0)
                    {
                        string badgeText = count.ToString();
                        var badgeFont    = AppFonts.MonoSmall;
                        var badgeSize    = g.MeasureString(badgeText, badgeFont);
                        int badgeW       = Math.Max((int)badgeSize.Width + 10, 22);
                        int badgeH       = 18;
                        int badgeX       = panelWidth - badgeW - 10;
                        int badgeY       = yOffset + (NAV_ITEM_HEIGHT - badgeH) / 2;

                        using (var badgeBg = new SolidBrush(AppColors.BrandRedMuted))
                        {
                            g.FillRectangle(badgeBg, badgeX, badgeY, badgeW, badgeH);
                        }
                        using (var badgeFg = new SolidBrush(AppColors.TextPrimary))
                        {
                            g.DrawString(badgeText, badgeFont, badgeFg,
                                badgeX + (badgeW - badgeSize.Width) / 2,
                                badgeY + (badgeH - badgeSize.Height) / 2);
                        }
                    }
                }

                // Store the hit rect for mouse click detection
                item.HitRect = itemRect;
                yOffset += NAV_ITEM_HEIGHT;
            }

            // ── Bottom: current user ──────────────────────────────────
            int bottomY = _navPanel.Height - 50;
            using (var divPen = new Pen(AppColors.BorderSubtle))
                g.DrawLine(divPen, 0, bottomY, panelWidth, bottomY);

            string userName = AppSettingsManager.Instance.Requestor?.Name;
            if (!string.IsNullOrWhiteSpace(userName))
            {
                using (var userFont = AppFonts.Caption)
                using (var userBrush = new SolidBrush(AppColors.TextDim))
                {
                    g.DrawString("Signed in as", userFont, userBrush, NAV_ITEM_INDENT, bottomY + 8);
                    g.DrawString(userName, AppFonts.LabelBold,
                        new SolidBrush(AppColors.TextMuted), NAV_ITEM_INDENT, bottomY + 24);
                }
            }
            else
            {
                using (var userFont = AppFonts.Caption)
                using (var userBrush = new SolidBrush(AppColors.TextDim))
                    g.DrawString("Set up your profile →", userFont, userBrush, NAV_ITEM_INDENT, bottomY + 16);
            }
        }

        // ── Nav Mouse Hit Detection ───────────────────────────────────

        private void navPanel_MouseClick(object sender, MouseEventArgs e)
        {
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

        private void navPanel_MouseMove(object sender, MouseEventArgs e)
        {
            bool overItem = false;
            foreach (var item in _navItems)
            {
                if (!item.Separator && item.HitRect.Contains(e.Location))
                {
                    overItem = true;
                    break;
                }
            }
            _navPanel.Cursor = overItem ? Cursors.Hand : Cursors.Default;
        }

        // ── Form Closing — Save Window State ─────────────────────────

        private void MainShell_FormClosing(object sender, FormClosingEventArgs e)
        {
            var s = AppSettingsManager.Instance.Settings;

            if (this.WindowState == FormWindowState.Maximized)
            {
                s.WindowMaximized = true;
            }
            else
            {
                s.WindowMaximized = false;
                s.WindowX         = this.Location.X;
                s.WindowY         = this.Location.Y;
                s.WindowWidth     = this.Size.Width;
                s.WindowHeight    = this.Size.Height;
            }

            AppSettingsManager.Instance.SaveSettings();
        }

        // ── Form Load — default view ──────────────────────────────────

        private void MainShell_Load(object sender, EventArgs e)
        {
            // Activate the "New Onboarding" view by default
            _activeNavItem = _navItems.Find(n => n.Id == "new");
            ShowView(GetDashboardView(), _activeNavItem);
            _navPanel.Invalidate();
        }
    }

    // ── NavItem helper class ──────────────────────────────────────────

    internal class NavItem
    {
        public string        Id         { get; set; }
        public string        Icon       { get; set; }
        public string        Label      { get; set; }
        public Action        Action     { get; set; }
        public bool          Separator  { get; set; }
        public Func<int>     BadgeValue { get; set; }  // Returns a count for the badge
        public Rectangle     HitRect    { get; set; }  // Set during paint, used for click detection
    }
}
