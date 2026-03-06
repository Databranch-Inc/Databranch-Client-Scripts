// =============================================================
// ArnotOnboardingUtility — Theme/ThemeHelper.cs
// Version    : 1.0.0.0
// Author     : Sam Kirsch / Databranch
// Created    : 2026-02-28
// Modified   : 2026-02-28
// Description: Recursively applies Databranch dark theme to a
//              WinForms control tree. Call ApplyTheme(this) in
//              every Form and UserControl after adding controls.
//              Also provides static button style helpers.
// =============================================================
using System.Drawing;
using System.Windows.Forms;

namespace ArnotOnboardingUtility.Theme
{
    public static class ThemeHelper
    {
        /// <summary>
        /// Walks the control tree rooted at <paramref name="root"/> and
        /// applies Databranch dark theme colors based on control type.
        /// Custom-painted controls should override OnPaint and not rely
        /// solely on BackColor/ForeColor.
        /// </summary>
        public static void ApplyTheme(Control root)
        {
            ApplyToControl(root);
            foreach (Control child in root.Controls)
                ApplyTheme(child);
        }

        private static void ApplyToControl(Control c)
        {
            switch (c)
            {
                case Form f:
                    f.BackColor = AppColors.SurfaceBase;
                    f.ForeColor = AppColors.TextPrimary;
                    break;

                case Panel p:
                    p.BackColor = AppColors.SurfaceBase;
                    p.ForeColor = AppColors.TextSecondary;
                    break;

                case Label lbl:
                    lbl.BackColor = Color.Transparent;
                    lbl.ForeColor = AppColors.TextSecondary;
                    break;

                case TextBox tb:
                    tb.BackColor = AppColors.SurfaceRaised;
                    tb.ForeColor = AppColors.TextPrimary;
                    tb.BorderStyle = BorderStyle.FixedSingle;
                    break;

                case RichTextBox rtb:
                    rtb.BackColor = AppColors.SurfaceRaised;
                    rtb.ForeColor = AppColors.TextPrimary;
                    rtb.BorderStyle = BorderStyle.None;
                    break;

                case Button btn:
                    StyleAsPrimaryButton(btn);
                    break;

                case CheckBox cb:
                    cb.BackColor = Color.Transparent;
                    cb.ForeColor = AppColors.TextSecondary;
                    cb.FlatStyle = FlatStyle.Flat;
                    break;

                case RadioButton rb:
                    rb.BackColor = Color.Transparent;
                    rb.ForeColor = AppColors.TextSecondary;
                    rb.FlatStyle = FlatStyle.Flat;
                    break;

                case ComboBox combo:
                    combo.BackColor = AppColors.SurfaceRaised;
                    combo.ForeColor = AppColors.TextPrimary;
                    combo.FlatStyle = FlatStyle.Flat;
                    break;

                case ListBox lb:
                    lb.BackColor = AppColors.SurfaceCard;
                    lb.ForeColor = AppColors.TextSecondary;
                    lb.BorderStyle = BorderStyle.None;
                    break;

                case DataGridView dgv:
                    dgv.BackgroundColor = AppColors.SurfaceBase;
                    dgv.ForeColor = AppColors.TextSecondary;
                    dgv.GridColor = AppColors.BorderSubtle;
                    dgv.BorderStyle = BorderStyle.None;
                    dgv.ColumnHeadersDefaultCellStyle.BackColor = AppColors.SurfaceRaised;
                    dgv.ColumnHeadersDefaultCellStyle.ForeColor = AppColors.TextMuted;
                    dgv.ColumnHeadersDefaultCellStyle.SelectionBackColor = AppColors.SurfaceRaised;
                    dgv.DefaultCellStyle.BackColor = AppColors.SurfaceBase;
                    dgv.DefaultCellStyle.ForeColor = AppColors.TextSecondary;
                    dgv.DefaultCellStyle.SelectionBackColor = AppColors.SurfaceElevated;
                    dgv.DefaultCellStyle.SelectionForeColor = AppColors.TextPrimary;
                    dgv.AlternatingRowsDefaultCellStyle.BackColor = AppColors.SurfaceRaised;
                    dgv.EnableHeadersVisualStyles = false;
                    break;

                case GroupBox gb:
                    gb.BackColor = AppColors.SurfaceBase;
                    gb.ForeColor = AppColors.TextMuted;
                    break;
            }
        }

        // ── Button style helpers ───────────────────────────────────────

        /// <summary>Red primary action button.</summary>
        public static void StyleAsPrimaryButton(Button btn)
        {
            btn.BackColor = AppColors.BrandRedSoft;
            btn.ForeColor = AppColors.TextPrimary;
            btn.FlatStyle = FlatStyle.Flat;
            btn.FlatAppearance.BorderColor = AppColors.BrandRedMuted;
            btn.FlatAppearance.MouseOverBackColor = AppColors.BrandRed;
            btn.FlatAppearance.MouseDownBackColor = AppColors.BrandRedMuted;
            btn.Font = AppFonts.Button;
            btn.Cursor = Cursors.Hand;
        }

        /// <summary>Blue secondary action button.</summary>
        public static void StyleAsSecondaryButton(Button btn)
        {
            btn.BackColor = AppColors.BrandBlueDim;
            btn.ForeColor = AppColors.TextPrimary;
            btn.FlatStyle = FlatStyle.Flat;
            btn.FlatAppearance.BorderColor = AppColors.BrandBlueMuted;
            btn.FlatAppearance.MouseOverBackColor = AppColors.BrandBlueMuted;
            btn.FlatAppearance.MouseDownBackColor = AppColors.BrandBlueDim;
            btn.Font = AppFonts.Button;
            btn.Cursor = Cursors.Hand;
        }

        /// <summary>Subtle ghost button for tertiary / cancel actions.</summary>
        public static void StyleAsGhostButton(Button btn)
        {
            btn.BackColor = AppColors.SurfaceCard;
            btn.ForeColor = AppColors.TextSecondary;
            btn.FlatStyle = FlatStyle.Flat;
            btn.FlatAppearance.BorderColor = AppColors.BorderDefault;
            btn.FlatAppearance.MouseOverBackColor = AppColors.SurfaceElevated;
            btn.FlatAppearance.MouseDownBackColor = AppColors.SurfaceCard;
            btn.Font = AppFonts.Button;
            btn.Cursor = Cursors.Hand;
        }
    }
}
