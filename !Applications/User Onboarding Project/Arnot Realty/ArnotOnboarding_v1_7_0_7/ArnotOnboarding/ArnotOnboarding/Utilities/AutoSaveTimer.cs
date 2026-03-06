// =============================================================
// ArnotOnboarding — AutoSaveTimer.cs
// Version    : 1.0.0.0
// Author     : Sam Kirsch
// Company    : Databranch
// Created    : 2026-02-22
// Modified   : 2026-02-22
// Description: Debounced auto-save timer for the wizard. Resets on
//              every field change and fires the save callback only
//              after the user has paused typing for the configured
//              interval (default 750ms). Prevents hammering disk
//              on every keystroke while still ensuring no data loss.
//
//              Usage:
//                _autoSave = new AutoSaveTimer(750, () => SaveCurrentDraft());
//                // In any field TextChanged / CheckedChanged handler:
//                _autoSave.Bump();
//                // On wizard close:
//                _autoSave.Dispose();
// =============================================================

using System;
using System.Windows.Forms;

namespace ArnotOnboarding.Utilities
{
    /// <summary>
    /// Debounced save trigger. Each call to Bump() resets the countdown.
    /// The callback fires once the countdown expires without another Bump().
    /// Thread-safe via WinForms Timer (UI thread only).
    /// </summary>
    public class AutoSaveTimer : IDisposable
    {
        private readonly Timer   _timer;
        private readonly Action  _saveCallback;
        private bool             _disposed = false;

        /// <summary>True if a save is pending (timer is running).</summary>
        public bool IsPending => _timer.Enabled;

        /// <summary>
        /// Raised after each successful auto-save callback fires.
        /// Attach to update a "Saved" status label in the UI.
        /// </summary>
        public event EventHandler SaveFired;

        /// <param name="debounceMs">Milliseconds of idle time before save fires. Default 750.</param>
        /// <param name="saveCallback">The action to invoke when the debounce expires.</param>
        public AutoSaveTimer(int debounceMs, Action saveCallback)
        {
            if (saveCallback == null) throw new ArgumentNullException("saveCallback");

            _saveCallback = saveCallback;

            _timer          = new Timer();
            _timer.Interval = debounceMs > 0 ? debounceMs : 750;
            _timer.Tick    += OnTick;
        }

        /// <summary>
        /// Called on every field change. Resets the debounce countdown.
        /// If a save is already pending, the countdown restarts from zero.
        /// </summary>
        public void Bump()
        {
            if (_disposed) return;
            _timer.Stop();
            _timer.Start();
        }

        /// <summary>
        /// Fires the save callback immediately without waiting for the debounce,
        /// then stops the timer. Use on wizard page navigation or explicit save.
        /// </summary>
        public void FlushNow()
        {
            if (_disposed) return;
            _timer.Stop();
            ExecuteSave();
        }

        /// <summary>Stops the pending timer without saving. Use when discarding a draft.</summary>
        public void Cancel()
        {
            if (_disposed) return;
            _timer.Stop();
        }

        private void OnTick(object sender, EventArgs e)
        {
            _timer.Stop(); // Fire once only — not a repeating timer
            ExecuteSave();
        }

        private void ExecuteSave()
        {
            try
            {
                _saveCallback();
                SaveFired?.Invoke(this, EventArgs.Empty);
            }
            catch (Exception ex)
            {
                // Log but don't crash the UI thread on an auto-save failure
                System.Diagnostics.Debug.WriteLine($"[AutoSaveTimer] Save callback failed: {ex.Message}");
            }
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            _timer.Stop();
            _timer.Dispose();
        }
    }
}
