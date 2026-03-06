// =============================================================
// ArnotOnboardingUtility — Views/SettingsView.cs
// Version    : 1.0.2.0
// Author     : Sam Kirsch / Databranch
// Created    : 2026-02-28
// Modified   : 2026-02-28
// Description: Application settings view. Milestone 1 stub
//              shows AppData paths. Full settings implementation
//              (default JSON path, log dir override, console
//              font size) added in Milestone 6.
// =============================================================
using System;
using System.Drawing;
using System.IO;
using System.Windows.Forms;
using ArnotOnboardingUtility.Managers;
using ArnotOnboardingUtility.Theme;

namespace ArnotOnboardingUtility.Views
{
    public class SettingsView : UserControl
    {
        public SettingsView()
        {
            BackColor = AppColors.SurfaceBase;
            Dock      = DockStyle.Fill;
            BuildLayout();
        }

        private void BuildLayout()
        {
            // Body FIRST (Fill), header LAST (Top) — WinForms dock priority order
            var body = new Panel
            {
                Dock      = DockStyle.Fill,
                BackColor = AppColors.SurfaceBase,
                Padding   = new Padding(40, 32, 40, 32)
            };
            Controls.Add(body);

            // Header — added LAST so it claims top space
            var header = new Panel
            {
                Dock      = DockStyle.Top,
                Height    = 100,
                BackColor = AppColors.SurfaceVoid
            };
            header.Paint += (s, e) =>
            {
                using (var b = new SolidBrush(AppColors.TextDim))
                    e.Graphics.DrawString("APPLICATION", AppFonts.NavSection, b, 28, 26);
                using (var b = new SolidBrush(AppColors.TextPrimary))
                    e.Graphics.DrawString("Settings", AppFonts.Heading3, b, 28, 48);
                using (var pen = new Pen(AppColors.BorderSubtle))
                    e.Graphics.DrawLine(pen, 0, header.Height - 1, header.Width, header.Height - 1);
            };
            Controls.Add(header);

            int y = 0;

            AddSectionHeader(body, "Data Paths", ref y);

            AddPathRow(body, "Sessions Directory",
                       SessionManager.SessionsDir, ref y);

            AddPathRow(body, "Log Files Directory",
                       SessionManager.LogsDir, ref y);

            y += 24;
            AddSectionHeader(body, "About This Build", ref y);

            var ver = System.Reflection.Assembly.GetExecutingAssembly().GetName().Version;
            AddInfoRow(body, "Version",
                       $"{ver.Major}.{ver.Minor}.{ver.Build}.{ver.Revision}", ref y);
            AddInfoRow(body, "Framework", ".NET Framework 4.8 / WinForms", ref y);
            AddInfoRow(body, "JSON Schema", "ArnotOnboarding schemaVersion 1.3", ref y);

            y += 24;
            var notice = new Label
            {
                Text      = "Full settings (default JSON path, console font size, etc.)\nare implemented in Milestone 6.",
                Font      = AppFonts.BodySmall,
                ForeColor = AppColors.TextDim,
                BackColor = Color.Transparent,
                Bounds    = new Rectangle(0, y, 600, 40)
            };
            body.Controls.Add(notice);
        }

        private void AddSectionHeader(Panel parent, string title, ref int y)
        {
            var lbl = new Label
            {
                Text      = title.ToUpper(),
                Font      = AppFonts.NavSection,
                ForeColor = AppColors.TextDim,
                BackColor = Color.Transparent,
                Bounds    = new Rectangle(0, y, 600, 18)
            };
            parent.Controls.Add(lbl);
            y += 26;
        }

        private void AddPathRow(Panel parent, string label, string path, ref int y)
        {
            var lblName = new Label
            {
                Text      = label,
                Font      = AppFonts.LabelBold,
                ForeColor = AppColors.TextMuted,
                BackColor = Color.Transparent,
                Bounds    = new Rectangle(0, y, 200, 18)
            };
            parent.Controls.Add(lblName);

            var lblPath = new Label
            {
                Text         = path,
                Font         = AppFonts.MonoSmall,
                ForeColor    = AppColors.BrandBluePale,
                BackColor    = Color.Transparent,
                Bounds       = new Rectangle(200, y, 480, 18),
                AutoEllipsis = true
            };
            parent.Controls.Add(lblPath);

            bool exists = Directory.Exists(path);
            var indicator = new Label
            {
                Text      = exists ? "● Exists" : "● Not found",
                Font      = AppFonts.Caption,
                ForeColor = exists ? AppColors.StatusSuccess : AppColors.StatusError,
                BackColor = Color.Transparent,
                Bounds    = new Rectangle(0, y + 20, 200, 14)
            };
            parent.Controls.Add(indicator);

            y += 48;
        }

        private void AddInfoRow(Panel parent, string label, string value, ref int y)
        {
            var lblName = new Label
            {
                Text      = label,
                Font      = AppFonts.Label,
                ForeColor = AppColors.TextMuted,
                BackColor = Color.Transparent,
                Bounds    = new Rectangle(0, y, 200, 18)
            };
            parent.Controls.Add(lblName);

            var lblValue = new Label
            {
                Text      = value,
                Font      = AppFonts.Mono,
                ForeColor = AppColors.TextSecondary,
                BackColor = Color.Transparent,
                Bounds    = new Rectangle(200, y, 480, 18)
            };
            parent.Controls.Add(lblValue);
            y += 28;
        }
    }
}
