// =============================================================
// ArnotOnboarding — LockManager.cs
// Version    : 1.0.0.0
// Author     : Sam Kirsch
// Company    : Databranch
// Created    : 2026-02-28
// Modified   : 2026-02-28
// Description: Creates, checks, and releases .lock sidecar files
//              placed next to a finalized record's JSON on the
//              network share when that record is checked out for
//              editing (Restart Onboarding).
//
//              Lock file lives at: {jsonPath}.lock
//              Contains: who locked it, from which machine,
//              Windows user account, and when.
//
//              Stale threshold: 2 hours — locks older than this
//              are considered abandoned and can be overridden.
//
//              The lock is:
//                Created  → when Restart Onboarding is clicked
//                Released → when the draft is Finalized OR Deleted
//                Queried  → by the nav warning banner and by
//                           Restart button before allowing access
// =============================================================

using System;
using System.IO;
using ArnotOnboarding.Models;
using Newtonsoft.Json;

namespace ArnotOnboarding.Managers
{
    public static class LockManager
    {
        private static readonly JsonSerializerSettings _json = new JsonSerializerSettings
        {
            Formatting        = Formatting.Indented,
            NullValueHandling = NullValueHandling.Include
        };

        // ── Path Convention ──────────────────────────────────────────

        /// <summary>Returns the path of the .lock sidecar for a given network JSON path.</summary>
        public static string LockPath(string networkJsonPath)
            => networkJsonPath + ".lock";

        // ── Acquire ──────────────────────────────────────────────────

        /// <summary>
        /// Attempts to create a lock file next to the given network JSON.
        /// Returns LockResult.Success if the lock was created.
        /// Returns LockResult.LockedByOther if a fresh (non-stale) lock already exists.
        /// Returns LockResult.Stale if a stale lock exists (caller should prompt to override).
        /// Returns LockResult.Error for file system errors (e.g. network unreachable).
        /// </summary>
        public static LockAcquireResult TryAcquire(string networkJsonPath, string recordId)
        {
            string lockPath = LockPath(networkJsonPath);

            try
            {
                // ── Check for existing lock ──────────────────────────
                if (File.Exists(lockPath))
                {
                    LockFile existing = TryReadLock(lockPath);

                    if (existing == null)
                    {
                        // Unreadable lock — treat as stale, return stale result
                        return new LockAcquireResult
                        {
                            Status    = LockAcquireStatus.Stale,
                            ExistingLock = new LockFile
                            {
                                LockedBy        = "Unknown",
                                LockedByMachine = "Unknown",
                                LockedByUser    = "Unknown",
                                LockedAt        = DateTime.UtcNow - LockFile.StaleThreshold - TimeSpan.FromMinutes(1)
                            }
                        };
                    }

                    // Is this lock owned by this machine+user? (App restarted without cleanup)
                    if (IsOwnedByThisSession(existing))
                    {
                        // Re-use our own lock — refresh timestamp
                        existing.LockedAt = DateTime.UtcNow;
                        WriteLock(lockPath, existing);
                        return new LockAcquireResult { Status = LockAcquireStatus.Success };
                    }

                    // Is it stale?
                    if (existing.IsStale)
                        return new LockAcquireResult { Status = LockAcquireStatus.Stale, ExistingLock = existing };

                    // Fresh lock held by someone else
                    return new LockAcquireResult { Status = LockAcquireStatus.LockedByOther, ExistingLock = existing };
                }

                // ── No existing lock — create one ────────────────────
                var lockFile = BuildLockFile(recordId);
                WriteLock(lockPath, lockFile);
                return new LockAcquireResult { Status = LockAcquireStatus.Success };
            }
            catch (Exception ex)
            {
                return new LockAcquireResult
                {
                    Status       = LockAcquireStatus.Error,
                    ErrorMessage = ex.Message
                };
            }
        }

        /// <summary>
        /// Forces creation of a lock file, overwriting any existing one.
        /// Use only after the user confirms they want to override a stale lock.
        /// </summary>
        public static bool ForceAcquire(string networkJsonPath, string recordId)
        {
            try
            {
                string lockPath = LockPath(networkJsonPath);
                var lockFile = BuildLockFile(recordId);
                WriteLock(lockPath, lockFile);
                return true;
            }
            catch { return false; }
        }

        // ── Release ──────────────────────────────────────────────────

        /// <summary>
        /// Deletes the lock file for the given network JSON path.
        /// Only deletes if the lock is owned by this session (safety check).
        /// Pass force=true to delete regardless of ownership (e.g. cleanup on uninstall).
        /// Returns true if the lock was released or did not exist.
        /// </summary>
        public static bool Release(string networkJsonPath, bool force = false)
        {
            if (string.IsNullOrEmpty(networkJsonPath)) return true;

            string lockPath = LockPath(networkJsonPath);

            try
            {
                if (!File.Exists(lockPath)) return true;

                if (!force)
                {
                    LockFile existing = TryReadLock(lockPath);
                    if (existing != null && !IsOwnedByThisSession(existing))
                        return false;   // Not our lock — don't release
                }

                File.Delete(lockPath);
                return true;
            }
            catch { return false; }
        }

        // ── Query ────────────────────────────────────────────────────

        /// <summary>
        /// Checks whether a network JSON is currently locked by someone else.
        /// Returns null if not locked or locked by this session (i.e. safe to proceed).
        /// Returns the LockFile if locked by another user.
        /// </summary>
        public static LockFile GetForeignLock(string networkJsonPath)
        {
            if (string.IsNullOrEmpty(networkJsonPath)) return null;

            string lockPath = LockPath(networkJsonPath);
            if (!File.Exists(lockPath)) return null;

            LockFile lf = TryReadLock(lockPath);
            if (lf == null) return null;
            if (IsOwnedByThisSession(lf)) return null;   // Our own lock — not foreign
            if (lf.IsStale) return null;                  // Stale — treat as not locked

            return lf;
        }

        /// <summary>
        /// Returns true if a valid, non-stale lock file exists that is NOT owned by this session.
        /// Fast check for UI enable/disable decisions.
        /// </summary>
        public static bool IsLockedByOther(string networkJsonPath)
            => GetForeignLock(networkJsonPath) != null;

        // ── Helpers ──────────────────────────────────────────────────

        private static LockFile BuildLockFile(string recordId) => new LockFile
        {
            RecordId        = recordId,
            LockedBy        = AppSettingsManager.Instance.Requestor?.Name ?? Environment.UserName,
            LockedByMachine = Environment.MachineName,
            LockedByUser    = Environment.UserName,
            LockedAt        = DateTime.UtcNow
        };

        private static bool IsOwnedByThisSession(LockFile lf)
            => string.Equals(lf.LockedByMachine, Environment.MachineName,
                   StringComparison.OrdinalIgnoreCase)
            && string.Equals(lf.LockedByUser, Environment.UserName,
                   StringComparison.OrdinalIgnoreCase);

        private static void WriteLock(string lockPath, LockFile lf)
        {
            string json = JsonConvert.SerializeObject(lf, _json);
            File.WriteAllText(lockPath, json);
        }

        private static LockFile TryReadLock(string lockPath)
        {
            try
            {
                string json = File.ReadAllText(lockPath);
                return JsonConvert.DeserializeObject<LockFile>(json);
            }
            catch { return null; }
        }
    }

    // ── Result types ─────────────────────────────────────────────────

    public enum LockAcquireStatus
    {
        Success,        // Lock created — proceed
        LockedByOther,  // Fresh lock held by someone else — block
        Stale,          // Lock exists but is old — prompt to override
        Error           // File system error — warn and block
    }

    public class LockAcquireResult
    {
        public LockAcquireStatus Status       { get; set; }
        public LockFile          ExistingLock { get; set; }  // Populated for LockedByOther / Stale
        public string            ErrorMessage { get; set; }  // Populated for Error
    }
}
