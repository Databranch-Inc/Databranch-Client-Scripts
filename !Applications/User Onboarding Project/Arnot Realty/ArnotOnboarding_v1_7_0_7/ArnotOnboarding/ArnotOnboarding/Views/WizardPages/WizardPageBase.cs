// =============================================================
// ArnotOnboarding — WizardPageBase.cs
// Version    : 1.0.0.0
// Author     : Sam Kirsch
// Company    : Databranch
// Created    : 2026-02-22
// Modified   : 2026-02-22
// Description: Abstract base UserControl for all wizard pages.
//              Provides shared layout helpers, field wiring, two-column
//              layout constants, and the DataChanged event raise helper.
//              All 13 wizard pages inherit from this class.
// =============================================================

using System;
using System.Drawing;
using System.Windows.Forms;
using ArnotOnboarding.Models;
using ArnotOnboarding.Theme;

namespace ArnotOnboarding.Views.WizardPages
{
    public abstract class WizardPageBase : UserControl, IWizardPage
    {
        // ── IWizardPage ──────────────────────────────────────────────
        public abstract string PageTitle { get; }
        public abstract void   LoadData(OnboardingRecord record);
        public abstract OnboardingRecord SaveData(OnboardingRecord record);
        public virtual new string Validate() { return null; } // Most pages have no required fields

        public event EventHandler DataChanged;

        // ── Layout Constants ─────────────────────────────────────────
        // Two-column layout: labels on the left, fields on the right.
        protected const int COL_LABEL_X      = 24;
        protected const int COL_LABEL_W      = 180;
        protected const int COL_FIELD_X      = 212;
        protected const int COL_FIELD_W      = 380;
        protected const int COL_FIELD_W_WIDE = 520;  // Full width fields (notes, lists)
        protected const int ROW_HEIGHT       = 46;   // Increased for comfortable spacing
        protected const int ROW_HEIGHT_TALL  = 58;
        protected const int START_Y          = 20;   // Page content starts here — extra top room prevents clip
        protected const int SECTION_GAP      = 20;
        protected const int CHECKBOX_X       = 212;
        protected const int RADIO_X          = 212;
        // Height allocated for a two-line label — must match ROW_HEIGHT
        protected const int LABEL_H_SINGLE   = 26;
        protected const int LABEL_H_DOUBLE   = 42;  // Two visible lines without clipping

        // ── Loading Guard ────────────────────────────────────────────
        // Set true during LoadData to suppress DataChanged events.
        protected bool _loading = false;

        // ── Constructor ──────────────────────────────────────────────
        protected WizardPageBase()
        {
            this.BackColor  = AppColors.SurfaceBase;
            this.ForeColor  = AppColors.TextSecondary;
            this.Font       = AppFonts.Body;
            // AutoScroll is FALSE — the _pageHost panel handles scrolling.
            // Child pages fill the host and render at absolute coordinates.
            this.AutoScroll = false;
            // No padding needed — START_Y constant provides the top offset.
            this.Padding    = new Padding(0);
        }

        // ── DataChanged Raise Helper ─────────────────────────────────

        /// <summary>
        /// Call from any field event handler to notify the WizardView that
        /// data has changed and the auto-save debounce should be bumped.
        /// Does nothing if _loading is true (prevents spurious saves on LoadData).
        /// </summary>
        protected void RaiseDataChanged()
        {
            if (!_loading)
                DataChanged?.Invoke(this, EventArgs.Empty);
        }

        // ── Layout Helpers ───────────────────────────────────────────

        /// <summary>
        /// Creates a right-aligned label for the left column.
        /// Height auto-adjusts: single-line labels are 26px, labels with a newline
        /// or long text get 44px so the second line is never clipped.
        /// The label is vertically centered on the field at position y.
        /// </summary>
        protected Label MakeLabel(string text, int y, bool bold = false)
        {
            bool multiLine = text.Contains("\n") || text.Length > 22;
            int  labelH    = multiLine ? LABEL_H_DOUBLE : LABEL_H_SINGLE;
            // Center the label vertically on the field row.
            // Field controls typically sit at y with height ~26.
            // For single-line: offset by (26-labelH)/2 to center on field.
            // For multi-line: anchor to the top of the row so both lines show.
            int  labelY    = multiLine ? y : y + 1;

            return new Label
            {
                Text      = text,
                Font      = bold ? AppFonts.LabelBold : AppFonts.Label,
                ForeColor = AppColors.TextSecondary,
                BackColor = Color.Transparent,
                Location  = new Point(COL_LABEL_X, labelY),
                Size      = new Size(COL_LABEL_W, labelH),
                TextAlign = multiLine ? ContentAlignment.TopRight : ContentAlignment.MiddleRight
            };
        }

        /// <summary>Creates a section divider label (e.g. "Step 7 — Domain Account").</summary>
        protected Label MakeSectionHeader(string text, int y)
        {
            return new Label
            {
                Text      = text,
                Font      = AppFonts.Heading3,
                ForeColor = AppColors.BrandRedPale,
                BackColor = Color.Transparent,
                Location  = new Point(COL_LABEL_X, y),
                Size      = new Size(COL_LABEL_W + COL_FIELD_W + 8, 22),
                TextAlign = ContentAlignment.MiddleLeft
            };
        }

        /// <summary>Creates a helper/note label below a field.</summary>
        protected Label MakeNoteLabel(string text, int y)
        {
            return new Label
            {
                Text      = text,
                Font      = AppFonts.Caption,
                ForeColor = AppColors.TextDim,
                BackColor = Color.Transparent,
                Location  = new Point(COL_FIELD_X, y),
                Size      = new Size(COL_FIELD_W, 18),
                TextAlign = ContentAlignment.MiddleLeft
            };
        }

        /// <summary>Creates a standard single-line TextBox in the right column.</summary>
        protected TextBox MakeTextBox(int y, int width = -1)
        {
            var tb = new TextBox
            {
                Location    = new Point(COL_FIELD_X, y),
                Size        = new Size(width < 0 ? COL_FIELD_W : width, 26),
                BackColor   = AppColors.SurfaceVoid,
                ForeColor   = AppColors.TextPrimary,
                BorderStyle = BorderStyle.FixedSingle,
                Font        = AppFonts.Body
            };
            tb.TextChanged += (s, e) => RaiseDataChanged();
            return tb;
        }

        /// <summary>Creates a multi-line TextBox with scrollbar.</summary>
        protected TextBox MakeMultiLineTextBox(int y, int height = 80, int width = -1)
        {
            var tb = new TextBox
            {
                Location    = new Point(COL_FIELD_X, y),
                Size        = new Size(width < 0 ? COL_FIELD_W : width, height),
                BackColor   = AppColors.SurfaceVoid,
                ForeColor   = AppColors.TextPrimary,
                BorderStyle = BorderStyle.FixedSingle,
                Font        = AppFonts.Body,
                Multiline   = true,
                ScrollBars  = ScrollBars.Vertical,
                WordWrap    = true
            };
            tb.TextChanged += (s, e) => RaiseDataChanged();
            return tb;
        }

        /// <summary>Creates a themed CheckBox in the right column.</summary>
        protected CheckBox MakeCheckBox(string text, int y, int xOffset = 0, int width = -1)
        {
            var cb = new CheckBox
            {
                Text      = text,
                Location  = new Point(CHECKBOX_X + xOffset, y),
                Size      = new Size(width > 0 ? width : COL_FIELD_W - xOffset, 26),
                BackColor = Color.Transparent,
                ForeColor = AppColors.TextSecondary,
                Font      = AppFonts.Body
            };
            cb.CheckedChanged += (s, e) => RaiseDataChanged();
            return cb;
        }

        /// <summary>Creates a themed RadioButton in the right column.</summary>
        protected RadioButton MakeRadioButton(string text, int y, int xOffset = 0)
        {
            var rb = new RadioButton
            {
                Text      = text,
                Location  = new Point(RADIO_X + xOffset, y),
                Size      = new Size(COL_FIELD_W - xOffset, 26),
                BackColor = Color.Transparent,
                ForeColor = AppColors.TextSecondary,
                Font      = AppFonts.Body
            };
            rb.CheckedChanged += (s, e) => RaiseDataChanged();
            return rb;
        }

        /// <summary>Creates a DateTimePicker for date-only selection.</summary>
        // ── Themed DateTimePicker helpers ────────────────────────────
        // DateTimePicker.BackColor doesn't theme the control face — the OS
        // always paints it with the system window color. We wrap each picker
        // in an owner-drawn Panel that provides our dark background and border,
        // then set the picker to fill the panel with no border of its own.
        // ShowCheckBox removed — dates are always required on this form.

        protected DateTimePicker MakeDatePicker(int y)
        {
            var dtp = new DateTimePicker
            {
                Location                = new Point(1, 1),
                Size                    = new Size(198, 24),
                Format                  = DateTimePickerFormat.Short,
                ShowCheckBox            = false,
                Value                   = DateTime.Today,
                BackColor               = AppColors.SurfaceVoid,
                ForeColor               = AppColors.TextPrimary,
                CalendarMonthBackground = AppColors.SurfaceCard,
                CalendarForeColor       = AppColors.TextPrimary,
                CalendarTitleBackColor  = AppColors.SurfaceRaised,
                CalendarTitleForeColor  = AppColors.TextPrimary,
                Font                    = AppFonts.Body
            };
            dtp.ValueChanged += (s, e) => RaiseDataChanged();

            var wrap = new Panel
            {
                Location  = new Point(COL_FIELD_X, y),
                Size      = new Size(200, 26),
                BackColor = AppColors.SurfaceVoid,
                Padding   = new System.Windows.Forms.Padding(1)
            };
            wrap.Paint += (s, pe) => {
                using (var pen = new System.Drawing.Pen(AppColors.BorderDefault))
                    pe.Graphics.DrawRectangle(pen, 0, 0, wrap.Width - 1, wrap.Height - 1);
            };
            wrap.Controls.Add(dtp);
            Controls.Add(wrap);
            return dtp;
        }

        /// <summary>Creates a themed DateTimePicker for time-only selection.</summary>
        protected DateTimePicker MakeTimePicker(int y)
        {
            var dtp = new DateTimePicker
            {
                Location   = new Point(1, 1),
                Size       = new Size(158, 24),
                Format     = DateTimePickerFormat.Time,
                ShowUpDown = true,
                BackColor  = AppColors.SurfaceVoid,
                ForeColor  = AppColors.TextPrimary,
                Font       = AppFonts.Body
            };
            dtp.ValueChanged += (s, e) => RaiseDataChanged();

            var wrap = new Panel
            {
                Location  = new Point(COL_FIELD_X + 210, y),
                Size      = new Size(160, 26),
                BackColor = AppColors.SurfaceVoid,
                Padding   = new System.Windows.Forms.Padding(1)
            };
            wrap.Paint += (s, pe) => {
                using (var pen = new System.Drawing.Pen(AppColors.BorderDefault))
                    pe.Graphics.DrawRectangle(pen, 0, 0, wrap.Width - 1, wrap.Height - 1);
            };
            wrap.Controls.Add(dtp);
            Controls.Add(wrap);
            return dtp;
        }

        /// <summary>
        /// Draws a subtle horizontal rule at the given Y position.
        /// Use as a visual section separator.
        /// </summary>
        protected Panel MakeDivider(int y)
        {
            return new Panel
            {
                Location  = new Point(COL_LABEL_X, y),
                Size      = new Size(COL_LABEL_W + COL_FIELD_W + 8, 1),
                BackColor = AppColors.BorderSubtle
            };
        }

        // ── Validation Helpers ───────────────────────────────────────

        /// <summary>
        /// Marks a TextBox as invalid by giving it a red border tint.
        /// Call ClearValidationError to reset it.
        /// </summary>
        protected void MarkInvalid(TextBox tb)
        {
            tb.BackColor = AppColors.StatusErrorBg;
        }

        protected void ClearValidationError(TextBox tb)
        {
            tb.BackColor = AppColors.SurfaceVoid;
        }
    }
}
