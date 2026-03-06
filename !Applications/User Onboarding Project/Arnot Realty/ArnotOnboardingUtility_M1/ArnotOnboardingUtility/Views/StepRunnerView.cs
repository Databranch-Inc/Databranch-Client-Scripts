// =============================================================
// ArnotOnboardingUtility — Views/StepRunnerView.cs
// Version    : 1.0.2.0
// Author     : Sam Kirsch / Databranch
// Created    : 2026-02-28
// Modified   : 2026-02-28
// Description: Workflow runner — M1 stub. Shows step list.
//              DockStyle.Fill added before DockStyle.Top header
//              so header stacks correctly at the top.
// =============================================================
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;
using ArnotOnboardingUtility.Managers;
using ArnotOnboardingUtility.Models;
using ArnotOnboardingUtility.Theme;

namespace ArnotOnboardingUtility.Views
{
    public class StepRunnerView : UserControl
    {
        public event EventHandler<EngineerSession> OnSessionUpdated;

        private readonly OnboardingRecord     _record;
        private          EngineerSession      _session;
        private readonly List<StepDefinition> _steps;
        private Label _lblProgress;

        public StepRunnerView(OnboardingRecord record, EngineerSession session)
        {
            _record  = record;
            _session = session;
            _steps   = StepCatalog.Build(record);
            BackColor = AppColors.SurfaceBase;
            Dock      = DockStyle.Fill;
            BuildLayout();
        }

        private void BuildLayout()
        {
            // ── Step list (Fill — add BEFORE Top so header wins) ──────
            var stepList = new Panel
            {
                Dock       = DockStyle.Fill,
                BackColor  = AppColors.SurfaceBase,
                AutoScroll = true,
                Padding    = new Padding(28, 16, 28, 16)
            };
            Controls.Add(stepList);

            // ── Header (Top — add LAST) ────────────────────────────────
            var header = new Panel
            {
                Dock      = DockStyle.Top,
                Height    = 100,
                BackColor = AppColors.SurfaceVoid,
                Padding   = new Padding(28, 0, 28, 0)
            };

            // Employee name — top of header zone
            var lblName = new Label
            {
                Text      = _record.FullName,
                Font      = AppFonts.Heading2,
                ForeColor = AppColors.TextPrimary,
                BackColor = Color.Transparent,
                AutoSize  = true,
                Location  = new Point(28, 18)
            };
            header.Controls.Add(lblName);

            // User type badge — custom-painted pill (avoids BorderStyle clipping)
            bool isKiosk       = _record.IsKioskUser;
            string badgeText   = isKiosk ? "Kiosk" : "Desktop";
            Color  badgeFg     = isKiosk ? AppColors.StatusWarn  : AppColors.BrandBlue;
            Color  badgeBg     = isKiosk ? AppColors.StatusWarnBg : AppColors.StatusInfoBg;
            Color  badgeBorder = isKiosk ? AppColors.StatusWarnBd : AppColors.BorderAccentBlue;

            var badge = new Panel
            {
                Location  = new Point(28, 56),
                Size      = new Size(60, 18),
                BackColor = badgeBg
            };
            badge.Paint += (s, e) =>
            {
                e.Graphics.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
                using (var pen = new Pen(badgeBorder))
                    e.Graphics.DrawRectangle(pen, 0, 0, badge.Width - 1, badge.Height - 1);
                var fmt = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
                using (var b = new SolidBrush(badgeFg))
                    e.Graphics.DrawString(badgeText, AppFonts.CaptionBold, b,
                                         new Rectangle(0, 0, badge.Width, badge.Height), fmt);
            };
            header.Controls.Add(badge);

            // Progress label — right of badge
            _lblProgress = new Label
            {
                Text      = _session.ProgressDisplay,
                Font      = AppFonts.BodySmall,
                ForeColor = AppColors.TextMuted,
                BackColor = Color.Transparent,
                AutoSize  = true,
                Location  = new Point(96, 58)
            };
            header.Controls.Add(_lblProgress);

            Controls.Add(header); // ← LAST among Top controls

            PopulateStepStubs(stepList);
        }

        private void PopulateStepStubs(Panel container)
        {
            container.Controls.Clear();
            string currentPhase = "";
            int y = 0;

            foreach (var step in _steps)
            {
                if (step.Phase != currentPhase)
                {
                    currentPhase = step.Phase;
                    container.Controls.Add(new Label
                    {
                        Text      = currentPhase.ToUpper(),
                        Font      = AppFonts.NavSection,
                        ForeColor = AppColors.TextDim,
                        BackColor = Color.Transparent,
                        Bounds    = new Rectangle(0, y, 800, 20)
                    });
                    y += 28;
                }

                bool isComplete = _session.StepIsComplete(step.Index);
                bool isActive   = step.Index == _session.CurrentStepIndex;

                var card = new Panel
                {
                    BackColor = isActive   ? AppColors.SurfaceElevated :
                               isComplete ? AppColors.SurfaceRaised   : AppColors.SurfaceCard,
                    Bounds    = new Rectangle(0, y, 700, 60),
                    Anchor    = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right
                };

                // Left accent
                card.Controls.Add(new Panel
                {
                    Bounds    = new Rectangle(0, 0, 4, 60),
                    BackColor = isActive   ? AppColors.BrandRedSoft  :
                               isComplete ? AppColors.StatusSuccess  : AppColors.BorderSubtle
                });

                // Step label
                card.Controls.Add(new Label
                {
                    Text      = step.StepLabel,
                    Font      = AppFonts.MonoSmall,
                    ForeColor = isComplete ? AppColors.StatusSuccess :
                               isActive   ? AppColors.TextPrimary   : AppColors.TextMuted,
                    BackColor = Color.Transparent,
                    Bounds    = new Rectangle(12, 8, 34, 20),
                    TextAlign = ContentAlignment.MiddleCenter
                });

                // Title
                card.Controls.Add(new Label
                {
                    Text      = step.Title,
                    Font      = isActive ? AppFonts.BodyBold : AppFonts.Body,
                    ForeColor = isActive   ? AppColors.TextPrimary  :
                               isComplete ? AppColors.TextSecondary : AppColors.TextMuted,
                    BackColor = Color.Transparent,
                    Bounds    = new Rectangle(52, 8, 480, 22)
                });

                // Type badge
                card.Controls.Add(new Label
                {
                    Text      = step.TypeLabel.ToUpper(),
                    Font      = AppFonts.CaptionBold,
                    ForeColor = step.Type == StepType.Automated ? AppColors.StatusSuccess :
                               step.Type == StepType.Hybrid    ? AppColors.StatusWarn    : AppColors.BrandBluePale,
                    BackColor = step.Type == StepType.Automated ? AppColors.StatusSuccessBg :
                               step.Type == StepType.Hybrid    ? AppColors.StatusWarnBg   : AppColors.StatusInfoBg,
                    Bounds      = new Rectangle(52, 34, 78, 16),
                    TextAlign   = ContentAlignment.MiddleCenter,
                    BorderStyle = BorderStyle.FixedSingle
                });

                // Status badge
                string statusText  = isComplete ? "✓ Complete" : isActive ? "● Active" : "Pending";
                Color  statusColor = isComplete ? AppColors.StatusSuccess :
                                    isActive    ? AppColors.StatusWarn    : AppColors.TextDim;
                card.Controls.Add(new Label
                {
                    Text      = statusText,
                    Font      = AppFonts.CaptionBold,
                    ForeColor = statusColor,
                    BackColor = Color.Transparent,
                    Bounds    = new Rectangle(560, 20, 120, 20),
                    TextAlign = ContentAlignment.MiddleRight,
                    Anchor    = AnchorStyles.Top | AnchorStyles.Right
                });

                card.Paint += (s, e) =>
                {
                    using (var pen = new Pen(AppColors.BorderSubtle))
                        e.Graphics.DrawLine(pen, 4, card.Height - 1, card.Width, card.Height - 1);
                };

                container.Controls.Add(card);
                y += 66;
            }

            container.Controls.Add(new Label
            {
                Text      = "Milestone 1 — Step cards are stubs.\nFull guidance, data fields, and script execution built in Milestone 2.",
                Font      = AppFonts.Caption,
                ForeColor = AppColors.TextDim,
                BackColor = Color.Transparent,
                Bounds    = new Rectangle(0, y + 16, 700, 36)
            });
        }

        // Called by MainShell event subscription — keeps compiler happy
        private void RaiseSessionUpdated()
            => OnSessionUpdated?.Invoke(this, _session);
    }
}
