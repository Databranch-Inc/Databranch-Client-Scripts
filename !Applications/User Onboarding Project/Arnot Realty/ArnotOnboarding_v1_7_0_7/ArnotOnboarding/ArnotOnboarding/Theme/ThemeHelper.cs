// =============================================================
// ArnotOnboarding — ThemeHelper.cs
// Version    : 1.0.0.0
// Author     : Sam Kirsch
// Company    : Databranch
// Created    : 2026-02-22
// Modified   : 2026-02-22
// Description: Applies the Databranch dark theme to WinForms controls.
//              Call ThemeHelper.ApplyTheme(this) in Form/UserControl Load.
//              Recurses through all child controls automatically.
// =============================================================

using System.Drawing;
using System.Windows.Forms;

namespace ArnotOnboarding.Theme
{
    public static class ThemeHelper
    {
        /// <summary>
        /// Recursively applies the dark theme to a control and all its children.
        /// Call once in form/usercontrol Load event.
        /// </summary>
        public static void ApplyTheme(Control root)
        {
            ApplyToControl(root);
            foreach (Control child in root.Controls)
                ApplyTheme(child);
        }

        private static void ApplyToControl(Control c)
        {
            // ── Form / Panel / UserControl surfaces ─────────────────
            if (c is Form || c is Panel || c is UserControl || c is TabPage)
            {
                c.BackColor = AppColors.SurfaceBase;
                c.ForeColor = AppColors.TextSecondary;
                c.Font = AppFonts.Body;
                return;
            }

            // ── GroupBox (card surface) ─────────────────────────────
            if (c is GroupBox gb)
            {
                gb.BackColor = AppColors.SurfaceCard;
                gb.ForeColor = AppColors.TextMuted;
                gb.Font = AppFonts.SectionLabel;
                return;
            }

            // ── Labels ─────────────────────────────────────────────
            if (c is Label lbl)
            {
                lbl.BackColor = Color.Transparent;
                lbl.ForeColor = AppColors.TextSecondary;
                lbl.Font = AppFonts.Label;
                return;
            }

            // ── TextBox ────────────────────────────────────────────
            if (c is TextBox tb)
            {
                tb.BackColor = AppColors.SurfaceVoid;
                tb.ForeColor = AppColors.TextPrimary;
                tb.BorderStyle = BorderStyle.FixedSingle;
                tb.Font = AppFonts.Body;
                return;
            }

            // ── RichTextBox ────────────────────────────────────────
            if (c is RichTextBox rtb)
            {
                rtb.BackColor = AppColors.SurfaceVoid;
                rtb.ForeColor = AppColors.TextPrimary;
                rtb.BorderStyle = BorderStyle.FixedSingle;
                rtb.Font = AppFonts.Body;
                return;
            }

            // ── ComboBox ───────────────────────────────────────────
            if (c is ComboBox cb)
            {
                cb.BackColor = AppColors.SurfaceVoid;
                cb.ForeColor = AppColors.TextPrimary;
                cb.FlatStyle = FlatStyle.Flat;
                cb.Font = AppFonts.Body;
                return;
            }

            // ── CheckBox ───────────────────────────────────────────
            if (c is CheckBox chk)
            {
                chk.BackColor = Color.Transparent;
                chk.ForeColor = AppColors.TextSecondary;
                chk.Font = AppFonts.Body;
                return;
            }

            // ── RadioButton ────────────────────────────────────────
            if (c is RadioButton rb)
            {
                rb.BackColor = Color.Transparent;
                rb.ForeColor = AppColors.TextSecondary;
                rb.Font = AppFonts.Body;
                return;
            }

            // ── Button — two styles: Primary (red) and Secondary (blue) ─
            // Tag the button with "primary" or "secondary" to pick style.
            if (c is Button btn)
            {
                ApplyButtonStyle(btn, (string)btn.Tag == "secondary"
                    ? ButtonStyle.Secondary
                    : ButtonStyle.Primary);
                return;
            }

            // ── DateTimePicker ─────────────────────────────────────
            if (c is DateTimePicker dtp)
            {
                dtp.BackColor = AppColors.SurfaceVoid;
                dtp.ForeColor = AppColors.TextPrimary;
                dtp.CalendarMonthBackground = AppColors.SurfaceCard;
                dtp.CalendarForeColor = AppColors.TextPrimary;
                dtp.CalendarTitleBackColor = AppColors.SurfaceRaised;
                dtp.CalendarTitleForeColor = AppColors.TextPrimary;
                dtp.Font = AppFonts.Body;
                return;
            }

            // ── ListBox / ListViewon ────────────────────────────────
            if (c is ListBox lb)
            {
                lb.BackColor = AppColors.SurfaceVoid;
                lb.ForeColor = AppColors.TextPrimary;
                lb.BorderStyle = BorderStyle.FixedSingle;
                lb.Font = AppFonts.Body;
                return;
            }

            if (c is ListView lv)
            {
                lv.BackColor = AppColors.SurfaceVoid;
                lv.ForeColor = AppColors.TextPrimary;
                lv.BorderStyle = BorderStyle.FixedSingle;
                lv.Font = AppFonts.Body;
                return;
            }

            // ── TabControl ─────────────────────────────────────────
            if (c is TabControl tc)
            {
                tc.BackColor = AppColors.SurfaceBase;
                tc.ForeColor = AppColors.TextSecondary;
                return;
            }

            // ── Separator / Splitter ───────────────────────────────
            if (c is SplitContainer sc)
            {
                sc.BackColor = AppColors.SurfaceBase;
                sc.Panel1.BackColor = AppColors.SurfaceRaised;
                sc.Panel2.BackColor = AppColors.SurfaceBase;
                return;
            }

            // ── Default fallback ───────────────────────────────────
            c.BackColor = AppColors.SurfaceBase;
            c.ForeColor = AppColors.TextSecondary;
        }

        // ── Button Styles ───────────────────────────────────────────
        public enum ButtonStyle { Primary, Secondary, Danger, Ghost }

        public static void ApplyButtonStyle(Button btn, ButtonStyle style)
        {
            btn.FlatStyle = FlatStyle.Flat;
            btn.Cursor = Cursors.Hand;
            btn.Font = AppFonts.Button;

            switch (style)
            {
                case ButtonStyle.Primary:   // Red — primary actions (Next, Finalize)
                    btn.BackColor = AppColors.BrandRedSoft;
                    btn.ForeColor = AppColors.TextPrimary;
                    btn.FlatAppearance.BorderColor = AppColors.BrandRedMuted;
                    btn.FlatAppearance.MouseOverBackColor = AppColors.BrandRed;
                    btn.FlatAppearance.MouseDownBackColor = AppColors.BrandRedMuted;
                    break;

                case ButtonStyle.Secondary: // Blue — secondary actions (Back, Save)
                    btn.BackColor = AppColors.BrandBlueMuted;
                    btn.ForeColor = AppColors.TextPrimary;
                    btn.FlatAppearance.BorderColor = AppColors.BrandBlueMid;
                    btn.FlatAppearance.MouseOverBackColor = AppColors.BrandBlue;
                    btn.FlatAppearance.MouseDownBackColor = AppColors.BrandBlueMid;
                    break;

                case ButtonStyle.Danger:    // Error red — destructive actions (Delete)
                    btn.BackColor = AppColors.StatusError;
                    btn.ForeColor = AppColors.TextPrimary;
                    btn.FlatAppearance.BorderColor = AppColors.StatusErrorBd;
                    btn.FlatAppearance.MouseOverBackColor = AppColors.BrandRedSoft;
                    btn.FlatAppearance.MouseDownBackColor = AppColors.BrandRedMuted;
                    break;

                case ButtonStyle.Ghost:     // Transparent — subtle actions
                    btn.BackColor = Color.Transparent;
                    btn.ForeColor = AppColors.TextMuted;
                    btn.FlatAppearance.BorderColor = AppColors.BorderDefault;
                    btn.FlatAppearance.MouseOverBackColor = AppColors.SurfaceElevated;
                    btn.FlatAppearance.MouseDownBackColor = AppColors.SurfaceOverlay;
                    break;
            }

            btn.FlatAppearance.BorderSize = 1;
        }
    }
}
