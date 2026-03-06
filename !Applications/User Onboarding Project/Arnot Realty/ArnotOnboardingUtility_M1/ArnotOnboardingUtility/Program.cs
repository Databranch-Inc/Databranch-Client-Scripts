// =============================================================
// ArnotOnboardingUtility — Program.cs
// Version    : 1.0.0.0
// Author     : Sam Kirsch / Databranch
// Created    : 2026-02-28
// Modified   : 2026-02-28
// Description: Application entry point.
// =============================================================
using System;
using System.Windows.Forms;

namespace ArnotOnboardingUtility
{
    static class Program
    {
        [STAThread]
        static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new Views.MainShell());
        }
    }
}
