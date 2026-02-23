// =============================================================
// ArnotOnboarding — Page13_MiscNotes.cs  v1.0.0.0
// Description: Miscellaneous notes and final action page.
//              Save & Close vs Finalize & Export buttons live here.
// =============================================================
using System.Windows.Forms;
using ArnotOnboarding.Models;
using ArnotOnboarding.Theme;

namespace ArnotOnboarding.Views.WizardPages
{
    public class Page13_MiscNotes : WizardPageBase
    {
        public override string PageTitle => "Notes & Finalize";

        private TextBox _txtNotes;

        public Page13_MiscNotes()
        {
            int y = START_Y;
            Controls.Add(MakeSectionHeader("Miscellaneous Notes", y)); y += 32;
            Controls.Add(MakeNoteLabel("Any additional information for the engineer handling this request.", y)); y += 24;

            Controls.Add(MakeLabel("Notes", y));
            _txtNotes = MakeMultiLineTextBox(y, 160, COL_FIELD_W_WIDE); y += 176;

            var summaryLabel = new Label
            {
                Text      = "When you're finished, use the buttons below to save your draft or finalize and export this request.",
                Location  = new System.Drawing.Point(COL_FIELD_X, y),
                Size      = new System.Drawing.Size(COL_FIELD_W_WIDE, 36),
                Font      = AppFonts.BodySmall,
                ForeColor = AppColors.TextMuted,
                BackColor = System.Drawing.Color.Transparent
            };
            Controls.Add(summaryLabel);

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
