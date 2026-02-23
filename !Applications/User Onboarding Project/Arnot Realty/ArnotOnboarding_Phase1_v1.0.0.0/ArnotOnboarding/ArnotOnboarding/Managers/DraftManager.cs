// =============================================================
// ArnotOnboarding — DraftManager.cs
// Version    : 1.0.0.0
// Author     : Sam Kirsch
// Company    : Databranch
// Created    : 2026-02-22
// Modified   : 2026-02-22
// Description: Manages in-progress (draft) onboarding records stored
//              locally in %AppData%\Databranch\ArnotOnboarding\Drafts\.
//
//              Responsibilities:
//              - Create new draft files when a wizard is started
//              - Write field changes to disk (called by auto-save debounce)
//              - Load a draft back into an OnboardingRecord for resumption
//              - Delete a draft on finalization or user deletion
//              - Export a draft as a portable .zip for transfer
//              - Import a portable .zip draft
//              - Maintain the draft index for the In Progress list view
// =============================================================

using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using ArnotOnboarding.Models;
using Newtonsoft.Json;

namespace ArnotOnboarding.Managers
{
    public class DraftManager
    {
        private readonly AppSettingsManager _appSettings;

        private readonly JsonSerializerSettings _jsonSettings = new JsonSerializerSettings
        {
            Formatting           = Formatting.Indented,
            NullValueHandling    = NullValueHandling.Include,
            DefaultValueHandling = DefaultValueHandling.Include
        };

        public DraftManager(AppSettingsManager appSettings)
        {
            _appSettings = appSettings;
        }

        // ── Path Helpers ────────────────────────────────────────────

        private string DraftPath(string recordId)
            => Path.Combine(AppSettingsManager.DraftsDirectory, $"{recordId}_draft.json");

        // ── Create ──────────────────────────────────────────────────

        /// <summary>
        /// Creates a brand-new draft record, saves it to disk, and adds it to the index.
        /// Call when the user clicks Next on wizard page 1 after entering an employee name.
        /// </summary>
        public OnboardingRecord CreateDraft(string firstName, string lastName, int startingPageIndex = 0)
        {
            var record = new OnboardingRecord
            {
                EmployeeFirstName = firstName,
                EmployeeLastName  = lastName,
                CreatedAt         = DateTime.Now,
                LastModified      = DateTime.Now,
                Status            = "draft"
            };

            // Auto-populate email using the customer profile
            record.EmailAddress = _appSettings.Customer.GenerateEmail(firstName, lastName);
            record.DomainUsername = _appSettings.Customer.GenerateUsername(firstName, lastName);

            SaveDraft(record);
            AddToIndex(record, startingPageIndex);
            return record;
        }

        // ── Save ────────────────────────────────────────────────────

        /// <summary>
        /// Writes the current state of a record to its draft JSON file.
        /// Updates LastModified timestamp. Called by the auto-save debounce.
        /// </summary>
        public void SaveDraft(OnboardingRecord record, int currentPageIndex = -1)
        {
            record.LastModified = DateTime.Now;
            string path = DraftPath(record.RecordId);
            string json = JsonConvert.SerializeObject(record, _jsonSettings);
            File.WriteAllText(path, json);

            // Keep the index entry's LastModified and page in sync
            UpdateIndexEntry(record, currentPageIndex);
        }

        // ── Load ────────────────────────────────────────────────────

        /// <summary>
        /// Loads a draft record from disk by its record ID.
        /// Returns null if the file does not exist.
        /// </summary>
        public OnboardingRecord LoadDraft(string recordId)
        {
            string path = DraftPath(recordId);
            if (!File.Exists(path))
                return null;

            string json = File.ReadAllText(path);
            return JsonConvert.DeserializeObject<OnboardingRecord>(json, _jsonSettings);
        }

        /// <summary>Loads a draft directly from a known full file path.</summary>
        public OnboardingRecord LoadDraftFromPath(string filePath)
        {
            if (!File.Exists(filePath))
                return null;

            string json = File.ReadAllText(filePath);
            return JsonConvert.DeserializeObject<OnboardingRecord>(json, _jsonSettings);
        }

        // ── Delete ──────────────────────────────────────────────────

        /// <summary>
        /// Deletes a draft file and removes it from the index.
        /// Called after successful finalization or explicit user deletion.
        /// </summary>
        public void DeleteDraft(string recordId)
        {
            string path = DraftPath(recordId);
            if (File.Exists(path))
                File.Delete(path);

            RemoveFromIndex(recordId);
        }

        // ── List ────────────────────────────────────────────────────

        /// <summary>
        /// Returns all current draft index entries, sorted by LastModified descending.
        /// Validates that each draft file still exists; removes stale index entries.
        /// </summary>
        public List<DraftIndexEntry> GetAllDrafts()
        {
            var index = _appSettings.LoadDraftIndex();
            var stale = new List<DraftIndexEntry>();

            foreach (var entry in index.Entries)
            {
                if (!File.Exists(entry.DraftFilePath))
                    stale.Add(entry);
            }

            // Clean up any orphaned index entries
            if (stale.Count > 0)
            {
                foreach (var s in stale)
                    index.Entries.Remove(s);
                _appSettings.SaveDraftIndex(index);
            }

            return index.Entries
                .OrderByDescending(e => e.LastModified)
                .ToList();
        }

        /// <summary>Returns true if any drafts currently exist locally.</summary>
        public bool HasDrafts() => GetAllDrafts().Count > 0;

        // ── Portable Export / Import ────────────────────────────────

        /// <summary>
        /// Exports a draft as a portable .zip file containing the draft JSON.
        /// The zip is named: ArnotOnboarding_Draft_{LastName}_{FirstName}_{date}.zip
        /// Returns the path of the created zip file.
        /// </summary>
        public string ExportDraftAsZip(string recordId, string destinationDirectory)
        {
            var record = LoadDraft(recordId);
            if (record == null)
                throw new FileNotFoundException($"Draft {recordId} not found.");

            string safeName = $"{record.EmployeeLastName}_{record.EmployeeFirstName}"
                .Replace(" ", "_")
                .Replace("/", "-")
                .Replace("\\", "-");

            string zipName = $"ArnotOnboarding_Draft_{safeName}_{DateTime.Now:yyyyMMdd}.zip";
            string zipPath = Path.Combine(destinationDirectory, zipName);

            // If a zip with this name already exists, add a counter suffix
            int counter = 1;
            while (File.Exists(zipPath))
            {
                zipPath = Path.Combine(destinationDirectory,
                    $"ArnotOnboarding_Draft_{safeName}_{DateTime.Now:yyyyMMdd}_{counter}.zip");
                counter++;
            }

            using (var zip = ZipFile.Open(zipPath, ZipArchiveMode.Create))
            {
                zip.CreateEntryFromFile(DraftPath(recordId),
                    $"{recordId}_draft.json",
                    CompressionLevel.Optimal);
            }

            return zipPath;
        }

        /// <summary>
        /// Imports a portable .zip draft. Extracts the JSON, assigns a new RecordId
        /// (to avoid collisions), saves it as a new local draft, and adds it to the index.
        /// Returns the loaded OnboardingRecord so the caller can open it in the wizard.
        /// </summary>
        public OnboardingRecord ImportDraftFromZip(string zipPath)
        {
            if (!File.Exists(zipPath))
                throw new FileNotFoundException($"Zip file not found: {zipPath}");

            string tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
            Directory.CreateDirectory(tempDir);

            try
            {
                ZipFile.ExtractToDirectory(zipPath, tempDir);

                // Find the draft JSON in the extracted files
                var jsonFiles = Directory.GetFiles(tempDir, "*_draft.json");
                if (jsonFiles.Length == 0)
                    throw new InvalidDataException("No valid draft JSON found in zip file.");

                string json   = File.ReadAllText(jsonFiles[0]);
                var record = JsonConvert.DeserializeObject<OnboardingRecord>(json, _jsonSettings);

                if (record == null)
                    throw new InvalidDataException("Draft JSON could not be parsed.");

                // Reassign a new RecordId to prevent collision with existing local drafts
                record.RecordId     = Guid.NewGuid().ToString();
                record.LastModified = DateTime.Now;
                record.Status       = "draft";

                // Clear export paths — this is now a local draft again
                record.ExportedPdfPath  = null;
                record.ExportedJsonPath = null;
                record.FinalizedAt      = null;

                SaveDraft(record);
                AddToIndex(record, 0);
                return record;
            }
            finally
            {
                // Always clean up temp directory
                try { Directory.Delete(tempDir, recursive: true); } catch { }
            }
        }

        // ── Index Maintenance (private) ─────────────────────────────

        private void AddToIndex(OnboardingRecord record, int pageIndex)
        {
            var index = _appSettings.LoadDraftIndex();

            // Don't add duplicates
            if (index.Entries.Exists(e => e.RecordId == record.RecordId))
            {
                UpdateIndexEntry(record, pageIndex);
                return;
            }

            index.Entries.Add(new DraftIndexEntry
            {
                RecordId      = record.RecordId,
                EmployeeName  = record.DisplayName,
                CreatedAt     = record.CreatedAt,
                LastModified  = record.LastModified,
                DraftFilePath = DraftPath(record.RecordId),
                LastPageIndex = pageIndex >= 0 ? pageIndex : 0
            });

            _appSettings.SaveDraftIndex(index);
        }

        private void UpdateIndexEntry(OnboardingRecord record, int pageIndex)
        {
            var index = _appSettings.LoadDraftIndex();
            var entry = index.Entries.Find(e => e.RecordId == record.RecordId);

            if (entry != null)
            {
                entry.EmployeeName = record.DisplayName;
                entry.LastModified = record.LastModified;
                if (pageIndex >= 0) entry.LastPageIndex = pageIndex;
                _appSettings.SaveDraftIndex(index);
            }
        }

        private void RemoveFromIndex(string recordId)
        {
            var index = _appSettings.LoadDraftIndex();
            index.Entries.RemoveAll(e => e.RecordId == recordId);
            _appSettings.SaveDraftIndex(index);
        }
    }
}
