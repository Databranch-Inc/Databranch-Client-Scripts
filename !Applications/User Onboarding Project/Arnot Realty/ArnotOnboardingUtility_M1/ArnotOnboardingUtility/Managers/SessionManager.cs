// =============================================================
// ArnotOnboardingUtility — Managers/SessionManager.cs
// Version    : 1.0.0.0
// Author     : Sam Kirsch / Databranch
// Created    : 2026-02-28
// Modified   : 2026-02-28
// Description: Manages EngineerSession JSON files in AppData.
//              Handles load, save, list, delete, and session
//              index maintenance for the LandingView recent-
//              sessions list. All paths are derived from a
//              single base directory constant.
// =============================================================
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using ArnotOnboardingUtility.Models;
using Newtonsoft.Json;

namespace ArnotOnboardingUtility.Managers
{
    public static class SessionManager
    {
        // ── AppData Paths ──────────────────────────────────────────────
        private static readonly string APP_DATA_BASE =
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                         "Databranch", "ArnotOnboardingUtility");

        public static readonly string SessionsDir = Path.Combine(APP_DATA_BASE, "Sessions");
        public static readonly string LogsDir     = Path.Combine(APP_DATA_BASE, "Logs");

        private static readonly string IndexPath  = Path.Combine(SessionsDir, "_index.json");

        // ── Initialization ────────────────────────────────────────────

        /// <summary>Ensures all AppData directories exist. Call once at startup.</summary>
        public static void EnsureDirectories()
        {
            Directory.CreateDirectory(SessionsDir);
            Directory.CreateDirectory(LogsDir);
        }

        // ── Session File Path ─────────────────────────────────────────

        private static string SessionPath(string recordId)
            => Path.Combine(SessionsDir, $"{recordId}.json");

        private static string LogPath(string recordId)
            => Path.Combine(LogsDir, $"{recordId}_session.log");

        // ── Load / Save ───────────────────────────────────────────────

        /// <summary>
        /// Loads an existing session for the given recordId,
        /// or returns null if no session exists yet.
        /// </summary>
        public static EngineerSession Load(string recordId)
        {
            var path = SessionPath(recordId);
            if (!File.Exists(path)) return null;
            try
            {
                var json = File.ReadAllText(path);
                return JsonConvert.DeserializeObject<EngineerSession>(json);
            }
            catch
            {
                return null; // Corrupt file — caller will create new session
            }
        }

        /// <summary>
        /// Saves the session to disk and updates the index.
        /// Safe to call frequently — no network writes occur.
        /// </summary>
        public static void Save(EngineerSession session)
        {
            if (session == null) return;
            try
            {
                session.LastWorked = DateTime.Now;
                var json = JsonConvert.SerializeObject(session, Formatting.Indented);
                File.WriteAllText(SessionPath(session.RecordId), json);
                UpdateIndex(session);
            }
            catch (Exception ex)
            {
                // Non-fatal — log to debug output but don't crash
                System.Diagnostics.Debug.WriteLine($"[SessionManager] Save failed: {ex.Message}");
            }
        }

        /// <summary>
        /// Creates a brand-new session from an OnboardingRecord.
        /// Assigns the log file path and saves immediately.
        /// </summary>
        public static EngineerSession CreateNew(OnboardingRecord record, string jsonSourcePath, List<StepDefinition> steps)
        {
            var session = new EngineerSession
            {
                RecordId       = record.RecordId,
                EmployeeName   = record.FullName,
                UserType       = record.IsKioskUser ? "Kiosk" : "Desktop",
                JsonSourcePath = jsonSourcePath,
                TotalSteps     = steps.Count,
                CurrentStepIndex = 0,
                SessionLogPath = LogPath(record.RecordId),
                StartedAt      = DateTime.Now,
                LastWorked     = DateTime.Now
            };
            Save(session);
            return session;
        }

        /// <summary>Deletes the session file and removes it from the index.</summary>
        public static void Delete(string recordId)
        {
            try
            {
                var path = SessionPath(recordId);
                if (File.Exists(path)) File.Delete(path);
                RemoveFromIndex(recordId);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[SessionManager] Delete failed: {ex.Message}");
            }
        }

        // ── Index ──────────────────────────────────────────────────────

        /// <summary>
        /// Returns all index entries, newest-last-worked first.
        /// Used by LandingView recent sessions list.
        /// </summary>
        public static List<SessionIndexEntry> GetAllSessions()
        {
            var index = LoadIndex();
            return index.Entries
                .OrderByDescending(e => e.LastWorked)
                .ToList();
        }

        private static SessionIndex LoadIndex()
        {
            if (!File.Exists(IndexPath)) return new SessionIndex();
            try
            {
                var json = File.ReadAllText(IndexPath);
                return JsonConvert.DeserializeObject<SessionIndex>(json) ?? new SessionIndex();
            }
            catch
            {
                return new SessionIndex();
            }
        }

        private static void UpdateIndex(EngineerSession session)
        {
            var index = LoadIndex();
            var existing = index.Entries.FirstOrDefault(e => e.RecordId == session.RecordId);
            if (existing != null)
                index.Entries.Remove(existing);

            index.Entries.Add(new SessionIndexEntry
            {
                RecordId       = session.RecordId,
                EmployeeName   = session.EmployeeName,
                UserType       = session.UserType,
                JsonSourcePath = session.JsonSourcePath,
                CurrentStepIndex = session.CurrentStepIndex,
                TotalSteps     = session.TotalSteps,
                IsComplete     = session.IsComplete,
                StartedAt      = session.StartedAt,
                LastWorked     = session.LastWorked
            });

            index.LastUpdated = DateTime.Now;
            SaveIndex(index);
        }

        private static void RemoveFromIndex(string recordId)
        {
            var index = LoadIndex();
            index.Entries.RemoveAll(e => e.RecordId == recordId);
            index.LastUpdated = DateTime.Now;
            SaveIndex(index);
        }

        private static void SaveIndex(SessionIndex index)
        {
            try
            {
                var json = JsonConvert.SerializeObject(index, Formatting.Indented);
                File.WriteAllText(IndexPath, json);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[SessionManager] Index save failed: {ex.Message}");
            }
        }

        // ── JSON Record Loader ─────────────────────────────────────────

        /// <summary>
        /// Loads and validates an OnboardingRecord from a JSON file path.
        /// Returns the record on success. Throws descriptive Exception on failure.
        /// </summary>
        public static OnboardingRecord LoadOnboardingRecord(string jsonPath)
        {
            if (!File.Exists(jsonPath))
                throw new FileNotFoundException($"File not found:\n{jsonPath}");

            string json;
            try
            {
                json = File.ReadAllText(jsonPath);
            }
            catch (Exception ex)
            {
                throw new InvalidOperationException($"Could not read file:\n{ex.Message}");
            }

            OnboardingRecord record;
            try
            {
                record = JsonConvert.DeserializeObject<OnboardingRecord>(json);
            }
            catch (JsonException ex)
            {
                throw new InvalidOperationException(
                    $"The selected file is not a valid onboarding record.\n\nDetails: {ex.Message}");
            }

            if (record == null)
                throw new InvalidOperationException("The file could not be parsed as an onboarding record.");

            if (string.IsNullOrWhiteSpace(record.RecordId))
                throw new InvalidOperationException("The record is missing a recordId field.");

            if (string.IsNullOrWhiteSpace(record.EmployeeFirstName) &&
                string.IsNullOrWhiteSpace(record.EmployeeLastName))
                throw new InvalidOperationException("The record is missing required employee name data.");

            // Warn (not block) on schema version mismatch — caller shows dialog
            const string EXPECTED_SCHEMA = "1.3";
            if (!string.Equals(record.SchemaVersion, EXPECTED_SCHEMA, StringComparison.Ordinal))
            {
                throw new SchemaMismatchException(
                    $"Schema version mismatch — expected {EXPECTED_SCHEMA}, found '{record.SchemaVersion}'.",
                    record);
            }

            if (!record.IsFinalized)
                throw new InvalidOperationException(
                    $"This record has not been finalized by HR.\n\nStatus: \"{record.Status}\"\n\n" +
                    "Only finalized records can be processed by this utility.");

            return record;
        }
    }

    /// <summary>
    /// Thrown when a record loads successfully but has an unexpected schema version.
    /// The record is still available so the caller can offer a "proceed anyway" option.
    /// </summary>
    public class SchemaMismatchException : Exception
    {
        public OnboardingRecord Record { get; }
        public SchemaMismatchException(string message, OnboardingRecord record)
            : base(message) { Record = record; }
    }
}
