// =============================================================
// ArnotOnboarding — Page02_Scheduling.cs  v1.0.0.0
// Description: Due dates and appointment scheduling.
// =============================================================
using System;
using System.Windows.Forms;
using ArnotOnboarding.Models;

namespace ArnotOnboarding.Views.WizardPages
{
    public class Page02_Scheduling : WizardPageBase
    {
        public override string PageTitle => "Due Dates & Scheduling";

        private DateTimePicker _dtpStartDate;
        private DateTimePicker _dtpApptDate;
        private DateTimePicker _dtpApptTime;
        private TextBox        _txtNotes;

        public Page02_Scheduling()
        {
            int y = START_Y;

            Controls.Add(MakeSectionHeader("Scheduling", y)); y += 32;

            Controls.Add(MakeLabel("Start Date", y));
            _dtpStartDate = MakeDatePicker(y); y += ROW_HEIGHT;

            Controls.Add(MakeLabel("Appointment Date", y));
            _dtpApptDate = MakeDatePicker(y);

            Controls.Add(MakeLabel("Appt. Time", y + ROW_HEIGHT - 6));
            _dtpApptTime = MakeTimePicker(y);
            _dtpApptTime.Location = new System.Drawing.Point(COL_FIELD_X, y + ROW_HEIGHT - 4);
            y += ROW_HEIGHT * 2;

            Controls.Add(MakeLabel("Scheduling Notes", y));
            _txtNotes = MakeMultiLineTextBox(y, 60); y += 72;

            Controls.AddRange(new Control[]
                { _dtpStartDate, _dtpApptDate, _dtpApptTime, _txtNotes });
        }

        public override void LoadData(OnboardingRecord r)
        {
            _loading = true;
            _dtpStartDate.Checked = r.StartDate.HasValue;
            if (r.StartDate.HasValue) _dtpStartDate.Value = r.StartDate.Value;

            _dtpApptDate.Checked = r.AppointmentDate.HasValue;
            if (r.AppointmentDate.HasValue) _dtpApptDate.Value = r.AppointmentDate.Value;

            if (r.AppointmentTime.HasValue)
                _dtpApptTime.Value = DateTime.Today.Add(r.AppointmentTime.Value);

            _txtNotes.Text = r.SchedulingNotes;
            _loading = false;
        }

        public override OnboardingRecord SaveData(OnboardingRecord r)
        {
            r.StartDate       = _dtpStartDate.Checked ? _dtpStartDate.Value.Date : (DateTime?)null;
            r.AppointmentDate = _dtpApptDate.Checked  ? _dtpApptDate.Value.Date  : (DateTime?)null;
            r.AppointmentTime = _dtpApptTime.Value.TimeOfDay;
            r.SchedulingNotes = _txtNotes.Text.Trim();
            return r;
        }
    }
}
