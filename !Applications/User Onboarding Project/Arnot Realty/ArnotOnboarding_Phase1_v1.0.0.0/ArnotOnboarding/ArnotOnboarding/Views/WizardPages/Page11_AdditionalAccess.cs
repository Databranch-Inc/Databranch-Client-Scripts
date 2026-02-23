// =============================================================
// ArnotOnboarding — Page11_AdditionalAccess.cs  v1.0.0.0
// Description: Additional access & security — Steps 19-20.
// =============================================================
using System.Collections.Generic;
using System.Windows.Forms;
using ArnotOnboarding.Managers;
using ArnotOnboarding.Models;

namespace ArnotOnboarding.Views.WizardPages
{
    public class Page11_AdditionalAccess : WizardPageBase
    {
        public override string PageTitle => "Additional Access & Security";

        private readonly List<CheckBox> _chkAdditional = new List<CheckBox>();
        private readonly List<CheckBox> _chkSecurity   = new List<CheckBox>();

        public Page11_AdditionalAccess()
        {
            int y = START_Y;
            var customer = AppSettingsManager.Instance.Customer;

            Controls.Add(MakeSectionHeader("Step 19 — Additional Access", y)); y += 32;
            foreach (string item in customer.AdditionalAccessList)
            {
                var cb = MakeCheckBox(item, y);
                _chkAdditional.Add(cb);
                Controls.Add(cb);
                y += 30;
            }

            y += SECTION_GAP;
            Controls.Add(MakeDivider(y)); y += 16;
            Controls.Add(MakeSectionHeader("Step 20 — Security Options", y)); y += 32;
            foreach (string item in customer.SecurityOptionsList)
            {
                var cb = MakeCheckBox(item, y);
                _chkSecurity.Add(cb);
                Controls.Add(cb);
                y += 30;
            }
        }

        public override void LoadData(OnboardingRecord r)
        {
            _loading = true;
            foreach (var cb in _chkAdditional) cb.Checked = r.AdditionalAccess.Contains(cb.Text);
            foreach (var cb in _chkSecurity)   cb.Checked = r.SecurityOptions.Contains(cb.Text);
            _loading = false;
        }

        public override OnboardingRecord SaveData(OnboardingRecord r)
        {
            r.AdditionalAccess.Clear();
            r.SecurityOptions.Clear();
            foreach (var cb in _chkAdditional) if (cb.Checked) r.AdditionalAccess.Add(cb.Text);
            foreach (var cb in _chkSecurity)   if (cb.Checked) r.SecurityOptions.Add(cb.Text);
            return r;
        }
    }
}
