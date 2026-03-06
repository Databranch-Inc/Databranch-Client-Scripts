// =============================================================
// ArnotOnboarding — Page01_Request.cs
// Version    : 1.5.9.0
// Description: Section 1 — Request dates. Dates are always required;
//              ShowCheckBox removed. Pickers are themed via WizardPageBase.
// =============================================================
using System;
using System.Windows.Forms;
using ArnotOnboarding.Models;

namespace ArnotOnboarding.Views.WizardPages
{
    public class Page01_Request : WizardPageBase
    {
        public override string PageTitle => "Request";

        private DateTimePicker _dtpCompletedBy;
        private DateTimePicker _dtpCompletedByTime;
        private DateTimePicker _dtpSetupAppt;
        private DateTimePicker _dtpSetupApptTime;

        public Page01_Request()
        {
            int y = START_Y;
            Controls.Add(MakeSectionHeader("Section 1 — Request", y)); y += 32;

            Controls.Add(MakeLabel("1a) Completed by (Date)", y));
            _dtpCompletedBy     = MakeDatePicker(y);
            _dtpCompletedByTime = MakeTimePicker(y);
            y += ROW_HEIGHT;

            Controls.Add(MakeLabel("1b) Setup Appt. (Date)", y));
            _dtpSetupAppt     = MakeDatePicker(y);
            _dtpSetupApptTime = MakeTimePicker(y);
        }

        public override void LoadData(OnboardingRecord r)
        {
            _loading = true;
            _dtpCompletedBy.Value     = r.CompletedByDate     ?? DateTime.Today;
            _dtpCompletedByTime.Value = r.CompletedByTime.HasValue
                ? DateTime.Today.Add(r.CompletedByTime.Value) : DateTime.Today;
            _dtpSetupAppt.Value       = r.SetupAppointmentDate ?? DateTime.Today;
            _dtpSetupApptTime.Value   = r.SetupAppointmentTime.HasValue
                ? DateTime.Today.Add(r.SetupAppointmentTime.Value) : DateTime.Today;
            _loading = false;
        }

        public override OnboardingRecord SaveData(OnboardingRecord r)
        {
            r.CompletedByDate      = _dtpCompletedBy.Value.Date;
            r.CompletedByTime      = _dtpCompletedByTime.Value.TimeOfDay;
            r.SetupAppointmentDate = _dtpSetupAppt.Value.Date;
            r.SetupAppointmentTime = _dtpSetupApptTime.Value.TimeOfDay;
            return r;
        }
    }
}
