// =============================================================
// ArnotOnboarding — RequestorView.cs
// Version    : 1.0.0.0
// Author     : Sam Kirsch
// Company    : Databranch
// Created    : 2026-02-22
// Modified   : 2026-02-22
// Description: "My Information" view. Lets the current user set their
//              name and contact info, which pre-fills wizard page 4.
//              Saves immediately to %AppData%\requestor.json.
// =============================================================

using System;
using System.Windows.Forms;
using ArnotOnboarding.Managers;
using ArnotOnboarding.Theme;

namespace ArnotOnboarding.Views
{
    public partial class RequestorView : UserControl
    {
        private bool _loading = false;

        public RequestorView()
        {
            InitializeComponent();
            ThemeHelper.ApplyTheme(this);
            LoadProfile();
            WireAutoSave();
        }

        private void LoadProfile()
        {
            _loading = true;
            var profile = AppSettingsManager.Instance.Requestor;
            _txtName.Text       = profile.Name;
            _txtTitle.Text      = profile.Title;
            _txtPhone.Text      = profile.Phone;
            _txtEmail.Text      = profile.Email;
            _txtDepartment.Text = profile.Department;
            _loading = false;
        }

        private void WireAutoSave()
        {
            _txtName.TextChanged       += OnFieldChanged;
            _txtTitle.TextChanged      += OnFieldChanged;
            _txtPhone.TextChanged      += OnFieldChanged;
            _txtEmail.TextChanged      += OnFieldChanged;
            _txtDepartment.TextChanged += OnFieldChanged;
        }

        private void OnFieldChanged(object sender, EventArgs e)
        {
            if (_loading) return;
            SaveProfile();
            _lblSaved.Text = "Saved ✓";
        }

        private void SaveProfile()
        {
            var profile        = AppSettingsManager.Instance.Requestor;
            profile.Name       = _txtName.Text.Trim();
            profile.Title      = _txtTitle.Text.Trim();
            profile.Phone      = _txtPhone.Text.Trim();
            profile.Email      = _txtEmail.Text.Trim();
            profile.Department = _txtDepartment.Text.Trim();
            AppSettingsManager.Instance.SaveRequestor();
        }
    }
}
