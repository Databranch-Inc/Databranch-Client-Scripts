// =============================================================
// ArnotOnboarding — Program.cs
// Version    : 1.0.0.0
// Author     : Sam Kirsch
// Company    : Databranch
// Created    : 2026-02-22
// Modified   : 2026-02-22
// Description: Application entry point. Initializes config managers
//              and launches the main shell form.
// =============================================================

using System;
using System.Windows.Forms;
using ArnotOnboarding.Managers;
using ArnotOnboarding.Views;

namespace ArnotOnboarding
{
    static class Program
    {
        [STAThread]
        static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            // Initialize all config/settings before any UI loads
            try
            {
                AppSettingsManager.Instance.Initialize();
            }
            catch (Exception ex)
            {
                MessageBox.Show(
                    $"Failed to initialize application settings:\n\n{ex.Message}\n\n" +
                    "The application will attempt to continue with defaults.",
                    "Initialization Warning",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Warning);
            }

            Application.Run(new MainShell());
        }
    }
}
