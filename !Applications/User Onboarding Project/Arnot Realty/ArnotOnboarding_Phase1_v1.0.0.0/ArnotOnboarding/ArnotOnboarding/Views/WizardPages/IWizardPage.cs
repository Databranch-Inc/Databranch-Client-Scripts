// =============================================================
// ArnotOnboarding — IWizardPage.cs
// Version    : 1.0.0.0
// Author     : Sam Kirsch
// Company    : Databranch
// Created    : 2026-02-22
// Modified   : 2026-02-22
// Description: Contract that every wizard page UserControl must
//              implement. The WizardView controller calls these
//              methods when navigating between pages.
// =============================================================

using System.Windows.Forms;
using ArnotOnboarding.Models;

namespace ArnotOnboarding.Views.WizardPages
{
    /// <summary>
    /// Interface every wizard page UserControl must implement.
    /// The WizardView controller calls LoadData on entry and SaveData
    /// before any navigation event (flush before moving).
    /// </summary>
    public interface IWizardPage
    {
        /// <summary>
        /// Title shown in the wizard progress bar subtitle.
        /// Keep short — one line.
        /// </summary>
        string PageTitle { get; }

        /// <summary>
        /// Populates all controls on this page from the supplied record.
        /// Called when the page becomes active. Must not trigger auto-save.
        /// </summary>
        void LoadData(OnboardingRecord record);

        /// <summary>
        /// Writes all control values back into the supplied record.
        /// Called before every navigation event (Back, Next, close).
        /// Returns the same record for convenience.
        /// </summary>
        OnboardingRecord SaveData(OnboardingRecord record);

        /// <summary>
        /// Validates required fields. Returns null if valid; otherwise
        /// returns a user-friendly error message to display.
        /// Only called on Next — not on Back.
        /// </summary>
        string Validate();

        /// <summary>
        /// Raised when any field changes so the WizardView can
        /// trigger the auto-save debounce timer.
        /// </summary>
        event System.EventHandler DataChanged;
    }
}
