// =============================================================
// ArnotOnboarding — Page07_Applications.cs  v1.0.0.0
// Description: Application selection — Step 9.
//              Checkbox list loaded from CustomerProfile.ApplicationsList.
// =============================================================
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;
using ArnotOnboarding.Managers;
using ArnotOnboarding.Models;

namespace ArnotOnboarding.Views.WizardPages
{
    public class Page07_Applications : WizardPageBase
    {
        public override string PageTitle => "Applications";

        private readonly List<CheckBox> _appCheckboxes = new List<CheckBox>();

        public Page07_Applications()
        {
            int y = START_Y;
            Controls.Add(MakeSectionHeader("Step 9 — Applications to Install", y)); y += 32;
            Controls.Add(MakeNoteLabel("Select all applications that should be installed for this user.", y)); y += 24;

            var apps = AppSettingsManager.Instance.Customer.ApplicationsList;
            foreach (string app in apps)
            {
                var cb = MakeCheckBox(app, y);
                cb.Location = new Point(COL_FIELD_X, y);
                _appCheckboxes.Add(cb);
                Controls.Add(cb);
                y += 30;
            }
        }

        public override void LoadData(OnboardingRecord r)
        {
            _loading = true;
            foreach (var cb in _appCheckboxes)
                cb.Checked = r.SelectedApplications.Contains(cb.Text);
            _loading = false;
        }

        public override OnboardingRecord SaveData(OnboardingRecord r)
        {
            r.SelectedApplications.Clear();
            foreach (var cb in _appCheckboxes)
                if (cb.Checked) r.SelectedApplications.Add(cb.Text);
            return r;
        }
    }
}
