// =============================================================
// ArnotOnboardingUtility — Views/LogViewerView.cs
// Version    : 1.0.2.0
// Author     : Sam Kirsch / Databranch
// Created    : 2026-02-28
// Modified   : 2026-02-28
// Description: Read-only session log viewer.
//              Toolbar pinned to BOTTOM, header docked TOP last.
// =============================================================
using System;
using System.Drawing;
using System.IO;
using System.Windows.Forms;
using ArnotOnboardingUtility.Theme;

namespace ArnotOnboardingUtility.Views
{
    public class LogViewerView : UserControl
    {
        private readonly string _logPath;
        private RichTextBox _rtb;

        public LogViewerView(string logPath)
        {
            _logPath  = logPath;
            BackColor = AppColors.SurfaceBase;
            Dock      = DockStyle.Fill;
            BuildLayout();
            LoadLog();
        }

        private void BuildLayout()
        {
            // ── Toolbar (Bottom — add first) ───────────────────────────
            var toolbar = new Panel
            {
                Dock      = DockStyle.Bottom,
                Height    = 44,
                BackColor = AppColors.SurfaceRaised
            };
            toolbar.Paint += (s, e) =>
            {
                using (var pen = new Pen(AppColors.BorderSubtle))
                    e.Graphics.DrawLine(pen, 0, 0, toolbar.Width, 0);
            };

            var btnRefresh = new Button { Text = "⟳  Refresh", Bounds = new Rectangle(12, 8, 110, 28) };
            ThemeHelper.StyleAsGhostButton(btnRefresh);
            btnRefresh.Click += (s, e) => LoadLog();
            toolbar.Controls.Add(btnRefresh);

            var btnOpen = new Button { Text = "Open in Notepad", Bounds = new Rectangle(130, 8, 138, 28) };
            ThemeHelper.StyleAsGhostButton(btnOpen);
            btnOpen.Click += (s, e) => OpenInNotepad();
            toolbar.Controls.Add(btnOpen);

            Controls.Add(toolbar);

            // ── Log RichTextBox (Fill — add before header) ────────────
            _rtb = new RichTextBox
            {
                Dock        = DockStyle.Fill,
                ReadOnly    = true,
                BackColor   = AppColors.ConsoleBg,
                ForeColor   = AppColors.TextSecondary,
                Font        = AppFonts.MonoSmall,
                BorderStyle = BorderStyle.None,
                ScrollBars  = RichTextBoxScrollBars.Vertical,
                WordWrap    = false
            };
            Controls.Add(_rtb);

            // ── Header (Top — add LAST) ────────────────────────────────
            var header = new Panel
            {
                Dock      = DockStyle.Top,
                Height    = 100,
                BackColor = AppColors.SurfaceVoid
            };
            header.Paint += (s, e) =>
            {
                var g = e.Graphics;
                g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
                using (var b = new SolidBrush(AppColors.TextDim))
                    g.DrawString("SESSION LOG", AppFonts.NavSection, b, 28, 26);
                using (var b = new SolidBrush(AppColors.TextPrimary))
                    g.DrawString("Script Execution History", AppFonts.Heading3, b, 28, 50);
                using (var pen = new Pen(AppColors.BorderSubtle))
                    g.DrawLine(pen, 0, header.Height - 1, header.Width, header.Height - 1);
            };
            Controls.Add(header); // ← LAST
        }

        private void LoadLog()
        {
            if (string.IsNullOrEmpty(_logPath) || !File.Exists(_logPath))
            {
                _rtb.ForeColor = AppColors.TextDim;
                _rtb.Text = _logPath == null
                    ? "No session is currently loaded."
                    : $"No log file yet.\nExpected: {_logPath}\n\nEntries appear here once scripts run (Milestone 3).";
                return;
            }
            try
            {
                _rtb.ForeColor = AppColors.TextSecondary;
                _rtb.Text      = File.ReadAllText(_logPath);
                _rtb.SelectionStart = _rtb.Text.Length;
                _rtb.ScrollToCaret();
            }
            catch (Exception ex)
            {
                _rtb.ForeColor = AppColors.StatusError;
                _rtb.Text = $"Error reading log:\n{ex.Message}";
            }
        }

        private void OpenInNotepad()
        {
            if (string.IsNullOrEmpty(_logPath) || !File.Exists(_logPath))
            {
                MessageBox.Show("No log file exists yet.", "Log Viewer",
                                MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            try { System.Diagnostics.Process.Start("notepad.exe", _logPath); }
            catch (Exception ex)
            {
                MessageBox.Show($"Could not open Notepad:\n{ex.Message}",
                                "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }
}
