// =============================================================
// ArnotOnboarding — AboutDialog.cs
// Version    : 1.0.0.0
// Author     : Sam Kirsch
// Company    : Databranch
// Created    : 2026-02-28
// Modified   : 2026-02-28
// Description: About / version dialog. Shows app name, version,
//              build date, author, and a full changelog summary.
//              Opened by clicking the logo/version area in the
//              nav rail, or pressing F1 anywhere in the shell.
// =============================================================

using System;
using System.Drawing;
using System.Reflection;
using System.Windows.Forms;
using ArnotOnboarding.Theme;

namespace ArnotOnboarding.Views
{
    public class AboutDialog : Form
    {
        // ── Changelog entries — newest first ──────────────────────────
        private static readonly (string Version, string Date, string[] Notes)[] _changelog =
        {
            ("v1.7.0.0", "2026-02-28", new[]
            {
                "LockManager: network .lock sidecar system for Restart Onboarding",
                "DraftManager: RestartFromRecord acquires lock before creating draft",
                "MainShell: amber warning banner shows count of locked in-progress records",
                "MainShell: FormClosing releases all session-owned locks as safety net",
                "RecordLibraryView: full lock negotiation flow on Restart (stale override, hard block)",
                "ExportManager: Finalize now calls DraftManager.DeleteDraft to release lock",
                "ExportManager: RequeryNetworkShare now prunes index entries missing from disk",
                "ExportManager: new DerivePdfPath() correctly maps JSON → PDF for both filename formats",
                "File naming: YYYYMMDD J Doe IT Onboard.pdf / IT Onboarding Data.json",
                "File dates use record.CreatedAt — re-export on later day keeps original date",
                "LockManager.cs registered in .csproj (was missing, caused CS0103 build errors)",
            }),
            ("v1.6.1.0", "2026-02-27", new[]
            {
                "LockFile model: added LockedByUser (Windows account), FriendlyDescription, DisplayName",
                "RecordLibraryView: Lock column shows owner, locked rows tinted amber",
                "RecordLibraryView: Restart button disabled with tooltip when locked by another user",
            }),
            ("v1.6.0.0", "2026-02-26", new[]
            {
                "RecordLibraryView: Restart Onboarding opens past record into a new editable draft",
                "Page06_Computer, Page08_Email: UI refinements and field corrections",
            }),
            ("v1.5.9.0", "2026-02-25", new[]
            {
                "Page01_Request: scheduling fields and section layout finalized",
            }),
            ("v1.5.8.0", "2026-02-24", new[]
            {
                "DraftListView: full resume, rename, delete, and import-from-zip workflow",
                "Page04_AccountsAndCredentials: conditional fields, domain username auto-suggest",
                "Page06b_MonitorsApps: dual-monitor radio sets, application checkbox grid",
                "Page07_PrintScanAccess: printer, scan-to-folder, shared folder grid",
            }),
            ("v1.5.0.0", "2026-02-23", new[]
            {
                "AppSettings: HrBasePath / HrSubPath network share configuration",
                "SettingsView: network path, requestor profile, index management",
                "ExportManager: PDF generation via MigraDoc, JSON export, Outlook email compose",
                "RecordLibraryView: indexed past records with PDF/JSON column indicators",
                "RequeryNetworkShare: scans HR share for records created on other machines",
            }),
            ("v1.3.0.0", "2026-02-22", new[]
            {
                "WizardView: 10-page wizard with Back/Next, step indicator, auto-save",
                "OnboardingRecord: full data model, schemaVersion, JSON serialization",
                "DraftManager: local %AppData% draft system, crash recovery on launch",
                "All wizard pages (01–10) implemented",
            }),
            ("v1.0.0.0", "2026-02-22", new[]
            {
                "Initial project: solution, MainShell nav rail, Databranch dark theme",
                "AppColors, AppFonts, ThemeHelper — full design token system",
                "CustomerProfile, RequestorProfile model classes",
            }),
        };

        public AboutDialog()
        {
            string ver   = GetAppVersion();
            string built = GetBuildDate();

            this.Text            = "About Arnot Onboarding";
            this.FormBorderStyle = FormBorderStyle.FixedDialog;
            this.MaximizeBox     = false;
            this.MinimizeBox     = false;
            this.StartPosition   = FormStartPosition.CenterParent;
            this.Size            = new Size(580, 620);
            this.BackColor       = AppColors.SurfaceCard;
            this.ForeColor       = AppColors.TextSecondary;
            this.KeyPreview      = true;
            this.KeyDown        += (s, e) => { if (e.KeyCode == Keys.Escape) this.Close(); };

            BuildLayout(ver, built);
        }

        private void BuildLayout(string ver, string built)
        {
            // ── Header banner ─────────────────────────────────────────
            var header = new Panel
            {
                Dock      = DockStyle.Top,
                Height    = 110,
                BackColor = AppColors.SurfaceVoid,
            };
            header.Paint += (s, e) =>
            {
                var g = e.Graphics;
                // Red accent bar
                using (var b = new SolidBrush(AppColors.BrandRedSoft))
                    g.FillRectangle(b, 0, 0, 4, header.Height);
                // Eyebrow
                using (var b = new SolidBrush(AppColors.BrandRedSoft))
                    g.DrawString("DATABRANCH", AppFonts.EyebrowLabel, b, 20, 20);
                // App name
                using (var b = new SolidBrush(AppColors.TextPrimary))
                using (var f = new Font("Segoe UI", 18f, FontStyle.Bold, GraphicsUnit.Point))
                    g.DrawString("Arnot Onboarding", f, b, 20, 38);
                // Version + build
                using (var b = new SolidBrush(AppColors.TextMuted))
                    g.DrawString($"{ver}  ·  Built {built}  ·  .NET Framework 4.8", AppFonts.Body, b, 20, 78);
                // Bottom divider
                using (var p = new Pen(AppColors.BorderDefault))
                    g.DrawLine(p, 0, header.Height - 1, header.Width, header.Height - 1);
            };
            this.Controls.Add(header);

            // ── Info row ─────────────────────────────────────────────
            var infoPanel = new Panel
            {
                Dock      = DockStyle.Top,
                Height    = 56,
                BackColor = AppColors.SurfaceRaised,
                Padding   = new Padding(20, 0, 20, 0),
            };
            infoPanel.Paint += (s, e) =>
            {
                var g = e.Graphics;
                using (var b = new SolidBrush(AppColors.TextMuted))
                {
                    g.DrawString("Author",  AppFonts.LabelBold, b, 20, 10);
                    g.DrawString("Client",  AppFonts.LabelBold, b, 190, 10);
                    g.DrawString("License", AppFonts.LabelBold, b, 360, 10);
                }
                using (var b = new SolidBrush(AppColors.TextPrimary))
                {
                    g.DrawString("Sam Kirsch",   AppFonts.Body, b, 20, 28);
                    g.DrawString("Arnot Realty", AppFonts.Body, b, 190, 28);
                    g.DrawString("Internal use", AppFonts.Body, b, 360, 28);
                }
                using (var p = new Pen(AppColors.BorderSubtle))
                    g.DrawLine(p, 0, infoPanel.Height - 1, infoPanel.Width, infoPanel.Height - 1);
            };
            this.Controls.Add(infoPanel);

            // ── Changelog header label ───────────────────────────────
            var lblChangelog = new Label
            {
                Text      = "CHANGELOG",
                Font      = AppFonts.EyebrowLabel,
                ForeColor = AppColors.BrandBlue,
                AutoSize  = false,
                Height    = 28,
                Dock      = DockStyle.Top,
                Padding   = new Padding(20, 10, 0, 0),
                BackColor = AppColors.SurfaceCard,
            };
            this.Controls.Add(lblChangelog);

            // ── Scrollable changelog body ────────────────────────────
            var scroll = new Panel
            {
                Dock        = DockStyle.Fill,
                AutoScroll  = true,
                BackColor   = AppColors.SurfaceCard,
                Padding     = new Padding(20, 8, 12, 8),
            };

            var inner = new FlowLayoutPanel
            {
                FlowDirection = FlowDirection.TopDown,
                WrapContents  = false,
                AutoSize      = true,
                AutoSizeMode  = AutoSizeMode.GrowAndShrink,
                Dock          = DockStyle.Top,
                BackColor     = AppColors.SurfaceCard,
                Padding       = new Padding(0),
            };

            foreach (var (version, date, notes) in _changelog)
            {
                // Version row
                var versionRow = new Panel
                {
                    Width     = 520,
                    Height    = 26,
                    BackColor = AppColors.SurfaceCard,
                    Margin    = new Padding(0, 6, 0, 2),
                };
                versionRow.Paint += (s, e) =>
                {
                    var g = e.Graphics;
                    // Version badge
                    var badgeRect = new Rectangle(0, 3, 62, 18);
                    using (var b = new SolidBrush(AppColors.StatusInfoBg))
                        g.FillRectangle(b, badgeRect);
                    using (var p = new Pen(AppColors.StatusInfoBd))
                        g.DrawRectangle(p, badgeRect);
                    using (var b = new SolidBrush(AppColors.BrandBlue))
                    using (var f = new Font("Consolas", 9f, FontStyle.Bold, GraphicsUnit.Point))
                        g.DrawString(version, f, b, 4, 5);
                    // Date
                    using (var b = new SolidBrush(AppColors.TextDim))
                        g.DrawString(date, AppFonts.Caption, b, 70, 7);
                };
                inner.Controls.Add(versionRow);

                // Note rows
                foreach (var note in notes)
                {
                    var noteLbl = new Label
                    {
                        Text      = "▸  " + note,
                        Font      = AppFonts.Body,
                        ForeColor = AppColors.TextSecondary,
                        AutoSize  = false,
                        Width     = 520,
                        Height    = 20,
                        Margin    = new Padding(0, 0, 0, 0),
                        BackColor = AppColors.SurfaceCard,
                    };
                    inner.Controls.Add(noteLbl);
                }
            }

            scroll.Controls.Add(inner);
            this.Controls.Add(scroll);

            // ── Footer close button ──────────────────────────────────
            var footer = new Panel
            {
                Dock      = DockStyle.Bottom,
                Height    = 52,
                BackColor = AppColors.SurfaceRaised,
            };
            footer.Paint += (s, e) =>
            {
                using (var p = new Pen(AppColors.BorderDefault))
                    e.Graphics.DrawLine(p, 0, 0, footer.Width, 0);
            };

            var btnClose = new Button
            {
                Text     = "Close",
                Size     = new Size(90, 32),
                Location = new Point(footer.Width - 110, 10),
                Anchor   = AnchorStyles.Right | AnchorStyles.Top,
            };
            ThemeHelper.ApplyButtonStyle(btnClose, ThemeHelper.ButtonStyle.Primary);
            btnClose.Click += (s, e) => this.Close();
            footer.Controls.Add(btnClose);
            this.Controls.Add(footer);

            // Dock order: Bottom must be added before Fill
            // WinForms processes Dock in reverse Controls order, so footer
            // is added last here which means it actually docks Bottom first.
        }

        // ── Helpers ──────────────────────────────────────────────────

        private static string GetAppVersion()
        {
            var v = Assembly.GetExecutingAssembly().GetName().Version;
            return v != null ? $"v{v.Major}.{v.Minor}.{v.Build}.{v.Revision}" : "v1.7.0.0";
        }

        private static string GetBuildDate()
        {
            // Use the assembly's last-write time as the build date.
            try
            {
                string path = Assembly.GetExecutingAssembly().Location;
                return System.IO.File.GetLastWriteTime(path).ToString("yyyy-MM-dd");
            }
            catch { return "2026-02-28"; }
        }
    }
}
