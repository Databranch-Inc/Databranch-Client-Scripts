// =============================================================
// ArnotOnboarding — DraftManager.cs
// Version    : 1.1.0.0
// Author     : Sam Kirsch
// Company    : Databranch
// Created    : 2026-02-22
// Modified   : 2026-02-28
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
//
// v1.1.0.0 — RestartFromRecord now accepts the source JSON network path
//             and stores it in the draft index entry as SourceJsonPath.
//             DeleteDraft now releases the .lock file for any draft
//             that has a SourceJsonPath (i.e. was a Restart).
//             ExportManager calls ReleaseLockForDraft after finalization.
//             Added GetLockedDrafts() for the nav warning banner.
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
            record.EmailAddress   = _appSettings.Customer.GenerateEmail(firstName, lastName);
            record.DomainUsername = _appSettings.Customer.GenerateUsername(firstName, lastName);

            SaveDraft(record);
            AddToIndex(record, startingPageIndex, sourceJsonPath: string.Empty);
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
            if (!File.Exists(path)) return null;

            string json = File.ReadAllText(path);
            return JsonConvert.DeserializeObject<OnboardingRecord>(json, _jsonSettings);
        }

        /// <summary>Loads a draft directly from a known full file path.</summary>
        public OnboardingRecord LoadDraftFromPath(string filePath)
        {
            if (!File.Exists(filePath)) return null;
            string json = File.ReadAllText(filePath);
            return JsonConvert.DeserializeObject<OnboardingRecord>(json, _jsonSettings);
        }

        // ── Delete ──────────────────────────────────────────────────

        /// <summary>
        /// Deletes a draft file and removes it from the index.
        /// If the draft has a SourceJsonPath (i.e. it was a Restart Onboarding),
        /// the .lock sidecar on the network share is released automatically.
        /// Called after successful finalization or explicit user deletion.
        /// </summary>
        public void DeleteDraft(string recordId)
        {
            // Release the network lock before deleting, so we know the SourceJsonPath
            ReleaseLockForDraft(recordId);

            string path = DraftPath(recordId);
            if (File.Exists(path))
                File.Delete(path);

            RemoveFromIndex(recordId);
        }

        /// <summary>
        /// Releases the network .lock file for a draft that has a SourceJsonPath.
        /// Safe to call even if the draft has no lock (no-op in that case).
        /// Called by ExportManager after successful finalization, and by
        /// DeleteDraft when the user discards a restarted draft.
        /// </summary>
        public void ReleaseLockForDraft(string recordId)
        {
            var index = _appSettings.LoadDraftIndex();
            var entry = index.Entries.Find(e => e.RecordId == recordId);

            if (entry != null && !string.IsNullOrEmpty(entry.SourceJsonPath))
            {
                LockManager.Release(entry.SourceJsonPath);
            }
        }

        // ── List ────────────────────────────────────────────────────

        /// <summary>
        /// Returns all current draft index entries, sorted by LastModified descending.
        /// Validates that each draft file still exists. Self-heals stale paths when
        /// the draft file is found in the canonical DraftsDirectory by RecordId.
        /// </summary>
        public List<DraftIndexEntry> GetAllDrafts()
        {
            var index  = _appSettings.LoadDraftIndex();
            var stale  = new List<DraftIndexEntry>();
            bool healed = false;

            foreach (var entry in index.Entries)
            {
                if (File.Exists(entry.DraftFilePath))
                    continue;   // path is fine

                // Try to find the file in the canonical drafts folder by RecordId
                string canonical = Path.Combine(
                    AppSettingsManager.DraftsDirectory,
                    $"{entry.RecordId}_draft.json");

                if (File.Exists(canonical))
                {
                    entry.DraftFilePath = canonical;
                    healed = true;
                }
                else
                {
                    stale.Add(entry);
                }
            }

            bool changed = healed || stale.Count > 0;

            if (stale.Count > 0)
            {
                // Release any locks held by drafts whose files are gone
                foreach (var s in stale)
                {
                    if (!string.IsNullOrEmpty(s.SourceJsonPath))
                        LockManager.Release(s.SourceJsonPath);
                }
                foreach (var s in stale)
                    index.Entries.Remove(s);
            }

            if (changed)
                _appSettings.SaveDraftIndex(index);

            return index.Entries
                .OrderByDescending(e => e.LastModified)
                .ToList();
        }

        /// <summary>Returns true if any drafts currently exist locally.</summary>
        public bool HasDrafts() => GetAllDrafts().Count > 0;

        /// <summary>
        /// Returns all draft index entries that have an active network lock
        /// (i.e. were created via Restart Onboarding and have a SourceJsonPath).
        /// Used by the nav warning banner to count and list locked records.
        /// </summary>
        public List<DraftIndexEntry> GetLockedDrafts()
        {
            return GetAllDrafts()
                .Where(e => e.HasNetworkLock)
                .ToList();
        }

        // ── Restart from finalized record ────────────────────────────

        /// <summary>
        /// Creates a new in-progress draft by copying a finalized OnboardingRecord.
        /// Acquires a .lock sidecar on the network JSON before doing so.
        ///
        /// Returns a RestartResult indicating success or the reason for failure
        /// (locked by another user, stale lock requiring override, or file error).
        ///
        /// On success, the draft index entry stores sourceJsonPath so the lock
        /// can be released when the draft is finalized or deleted.
        /// </summary>
        public RestartResult RestartFromRecord(OnboardingRecord source, string sourceJsonPath)
        {
            if (source == null)
                throw new ArgumentNullException(nameof(source));

            // ── Attempt to acquire the lock ──────────────────────────
            if (!string.IsNullOrEmpty(sourceJsonPath))
            {
                var lockResult = LockManager.TryAcquire(sourceJsonPath, source.RecordId);

                switch (lockResult.Status)
                {
                    case LockAcquireStatus.LockedByOther:
                        return new RestartResult
                        {
                            Success      = false,
                            Reason       = RestartFailReason.LockedByOther,
                            ExistingLock = lockResult.ExistingLock
                        };

                    case LockAcquireStatus.Stale:
                        return new RestartResult
                        {
                            Success      = false,
                            Reason       = RestartFailReason.StaleLock,
                            ExistingLock = lockResult.ExistingLock
                        };

                    case LockAcquireStatus.Error:
                        return new RestartResult
                        {
                            Success       = false,
                            Reason        = RestartFailReason.LockError,
                            ErrorMessage  = lockResult.ErrorMessage
                        };

                    case LockAcquireStatus.Success:
                        break;  // Continue below
                }
            }

            // ── Create the draft ─────────────────────────────────────
            string json  = JsonConvert.SerializeObject(source, _jsonSettings);
            var    clone = JsonConvert.DeserializeObject<OnboardingRecord>(json);

            clone.RecordId              = Guid.NewGuid().ToString("N");
            clone.Status                = "draft";
            clone.CreatedAt             = DateTime.Now;
            clone.LastModified          = DateTime.Now;
            clone.RestartedFromRecordId = source.RecordId;
            clone.RestartedAt           = DateTime.Now;

            clone.IsExported      = false;
            clone.ExportedAt      = null;
            clone.ExportPdfPath   = string.Empty;
            clone.ExportJsonPath  = string.Empty;
            clone.RecordIsNew     = false;

            SaveDraft(clone);
            AddToIndex(clone, pageIndex: 0, sourceJsonPath: sourceJsonPath ?? string.Empty);

            return new RestartResult { Success = true, NewDraft = clone };
        }

        /// <summary>
        /// Forces a lock acquisition (override a stale lock) and creates the draft.
        /// Call only after the user has confirmed they want to override the stale lock.
        /// </summary>
        public RestartResult ForceRestartFromRecord(OnboardingRecord source, string sourceJsonPath)
        {
            if (!string.IsNullOrEmpty(sourceJsonPath))
                LockManager.ForceAcquire(sourceJsonPath, source.RecordId);

            // Now restart without going through lock negotiation
            string json  = JsonConvert.SerializeObject(source, _jsonSettings);
            var    clone = JsonConvert.DeserializeObject<OnboardingRecord>(json);

            clone.RecordId              = Guid.NewGuid().ToString("N");
            clone.Status                = "draft";
            clone.CreatedAt             = DateTime.Now;
            clone.LastModified          = DateTime.Now;
            clone.RestartedFromRecordId = source.RecordId;
            clone.RestartedAt           = DateTime.Now;

            clone.IsExported      = false;
            clone.ExportedAt      = null;
            clone.ExportPdfPath   = string.Empty;
            clone.ExportJsonPath  = string.Empty;
            clone.RecordIsNew     = false;

            SaveDraft(clone);
            AddToIndex(clone, pageIndex: 0, sourceJsonPath: sourceJsonPath ?? string.Empty);

            return new RestartResult { Success = true, NewDraft = clone };
        }

        // ── Portable Export / Import ────────────────────────────────

        /// <summary>
        /// Exports a draft as a portable .zip file containing the draft JSON.
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
        /// Imports a portable .zip draft. Extracts the JSON, assigns a new RecordId,
        /// saves it as a new local draft, and adds it to the index.
        /// Note: imported drafts are treated as brand-new (no SourceJsonPath / no lock).
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

                var jsonFiles = Directory.GetFiles(tempDir, "*_draft.json");
                if (jsonFiles.Length == 0)
                    throw new InvalidDataException("No valid draft JSON found in zip file.");

                string json   = File.ReadAllText(jsonFiles[0]);
                var record = JsonConvert.DeserializeObject<OnboardingRecord>(json, _jsonSettings);

                if (record == null)
                    throw new InvalidDataException("Draft JSON could not be parsed.");

                record.RecordId     = Guid.NewGuid().ToString();
                record.LastModified = DateTime.Now;
                record.Status       = "draft";
                record.ExportPdfPath  = string.Empty;
                record.ExportJsonPath = string.Empty;
                record.ExportedAt     = null;

                SaveDraft(record);
                AddToIndex(record, 0, sourceJsonPath: string.Empty);
                return record;
            }
            finally
            {
                try { Directory.Delete(tempDir, recursive: true); } catch { }
            }
        }

        // ── Index Maintenance (private) ─────────────────────────────

        private void AddToIndex(OnboardingRecord record, int pageIndex, string sourceJsonPath)
        {
            var index = _appSettings.LoadDraftIndex();

            if (index.Entries.Exists(e => e.RecordId == record.RecordId))
            {
                UpdateIndexEntry(record, pageIndex);
                return;
            }

            index.Entries.Add(new DraftIndexEntry
            {
                RecordId       = record.RecordId,
                EmployeeName   = record.DisplayName,
                CreatedAt      = record.CreatedAt,
                LastModified   = record.LastModified,
                DraftFilePath  = DraftPath(record.RecordId),
                LastPageIndex  = pageIndex >= 0 ? pageIndex : 0,
                SourceJsonPath = sourceJsonPath ?? string.Empty
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

    // ── Restart result types ──────────────────────────────────────────

    public enum RestartFailReason
    {
        LockedByOther,  // A fresh lock is held by someone else
        StaleLock,      // A stale lock exists — user may override
        LockError       // File system error writing the lock
    }

    public class RestartResult
    {
        public bool             Success      { get; set; }
        public OnboardingRecord NewDraft     { get; set; }   // Populated on success
        public RestartFailReason Reason      { get; set; }   // Populated on failure
        public LockFile         ExistingLock { get; set; }   // Populated for LockedByOther / StaleLock
        public string           ErrorMessage { get; set; }   // Populated for LockError
    }
}
