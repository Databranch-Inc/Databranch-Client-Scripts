// =============================================================
// ArnotOnboarding — Page10_SoftwareAccess.cs  v1.0.0.0
// Description: Software & access rights — Steps 17-18.
// =============================================================
using System.Collections.Generic;
using System.Windows.Forms;
using ArnotOnboarding.Managers;
using ArnotOnboarding.Models;

namespace ArnotOnboarding.Views.WizardPages
{
    public class Page10_SoftwareAccess : WizardPageBase
    {
        public override string PageTitle => "Software & Access Rights";

        private readonly List<CheckBox> _chkSoftware = new List<CheckBox>();
        private readonly List<CheckBox> _chkAccess   = new List<CheckBox>();

        public Page10_SoftwareAccess()
        {
            int y = START_Y;
            var customer = AppSettingsManager.Instance.Customer;

            Controls.Add(MakeSectionHeader("Step 17 — Software Access", y)); y += 32;
            foreach (string item in customer.SoftwareAccessList)
            {
                var cb = MakeCheckBox(item, y);
                _chkSoftware.Add(cb);
                Controls.Add(cb);
                y += 30;
            }

            y += SECTION_GAP;
            Controls.Add(MakeDivider(y)); y += 16;
            Controls.Add(MakeSectionHeader("Step 18 — Access Rights", y)); y += 32;
            foreach (string item in customer.AccessRightsList)
            {
                var cb = MakeCheckBox(item, y);
                _chkAccess.Add(cb);
                Controls.Add(cb);
                y += 30;
            }
        }

        public override void LoadData(OnboardingRecord r)
        {
            _loading = true;
            foreach (var cb in _chkSoftware) cb.Checked = r.SoftwareAccess.Contains(cb.Text);
            foreach (var cb in _chkAccess)   cb.Checked = r.AccessRights.Contains(cb.Text);
            _loading = false;
        }

        public override OnboardingRecord SaveData(OnboardingRecord r)
        {
            r.SoftwareAccess.Clear();
            r.AccessRights.Clear();
            foreach (var cb in _chkSoftware) if (cb.Checked) r.SoftwareAccess.Add(cb.Text);
            foreach (var cb in _chkAccess)   if (cb.Checked) r.AccessRights.Add(cb.Text);
            return r;
        }
    }
}
