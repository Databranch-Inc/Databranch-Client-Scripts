// =============================================================
// ArnotOnboarding — Page10_ConfirmationNotes.cs  v1.3.0.0
// Form Steps 32-35: Confirmation & Misc. Setup + Notes
// These are Databranch engineer checklist items displayed for awareness,
// plus a free-form notes field.
// =============================================================
using System.Drawing;
using System.Windows.Forms;
using ArnotOnboarding.Models;
using ArnotOnboarding.Theme;

namespace ArnotOnboarding.Views.WizardPages
{
    public class Page10_ConfirmationNotes : WizardPageBase
    {
        public override string PageTitle => "Confirmation & Notes (Steps 32-35)";

        private TextBox _txtNotes;

        private static readonly string[] ENGINEER_STEPS = {
            "32 — Databranch engineer will sign into the user's computer and ensure all items " +
            "are setup before the user's first sign in",
            "33 — Databranch engineer – Confirm Arnot-custom Office templates – group policy deploys these now",
            "34 — Databranch engineer – Setup LastPass Extensions for logout after 15 Minutes",
            "35 — Databranch engineer – Confirm with the user which is their preferred browser. " +
            "Ensure that browser is set as default, and that LastPass extension is configured per above",
        };

        public Page10_ConfirmationNotes()
        {
            int y = START_Y;
            Controls.Add(MakeSectionHeader("Confirmation & Misc. Setup (Steps 32-35)", y)); y += 28;
            Controls.Add(MakeNoteLabel("The following steps are completed by the Databranch engineer during setup.", y)); y += 24;

            foreach (string step in ENGINEER_STEPS)
            {
                var lbl = new Label
                {
                    Text      = step,
                    Location  = new Point(COL_FIELD_X, y),
                    Size      = new Size(COL_FIELD_W_WIDE, 40),
                    Font      = AppFonts.BodySmall,
                    ForeColor = AppColors.BrandRedPale,
                    BackColor = AppColors.StatusInfoBg,
                    Padding   = new Padding(8, 6, 8, 6),
                    AutoEllipsis = false
                };
                Controls.Add(lbl);
                y += 48;
            }

            Controls.Add(MakeDivider(y)); y += 16;
            Controls.Add(MakeSectionHeader("Miscellaneous Notes", y)); y += 32;
            Controls.Add(MakeNoteLabel("Any additional notes or special instructions for the engineer:", y)); y += 22;

            Controls.Add(MakeLabel("Notes", y));
            _txtNotes = MakeMultiLineTextBox(y, 160, COL_FIELD_W_WIDE);
            Controls.Add(_txtNotes);
        }

        public override void LoadData(OnboardingRecord r)
        {
            _loading = true;
            _txtNotes.Text = r.MiscNotes;
            _loading = false;
        }

        public override OnboardingRecord SaveData(OnboardingRecord r)
        {
            r.MiscNotes = _txtNotes.Text.Trim();
            return r;
        }
    }
}
