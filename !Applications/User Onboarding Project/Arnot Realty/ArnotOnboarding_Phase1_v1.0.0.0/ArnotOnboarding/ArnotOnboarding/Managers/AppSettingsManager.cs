// =============================================================
// ArnotOnboarding — AppSettingsManager.cs
// Version    : 1.0.0.0
// Author     : Sam Kirsch
// Company    : Databranch
// Created    : 2026-02-22
// Modified   : 2026-02-22
// Description: Manages all persistent app configuration stored in
//              %AppData%\Databranch\ArnotOnboarding\. Handles initial
//              creation with defaults if files do not yet exist.
//              All JSON read/write goes through this class.
// =============================================================

using System;
using System.IO;
using ArnotOnboarding.Models;
using Newtonsoft.Json;

namespace ArnotOnboarding.Managers
{
    /// <summary>
    /// Singleton-style manager for all %AppData% configuration files.
    /// Call AppSettingsManager.Instance to access. Initialize once at startup.
    /// </summary>
    public class AppSettingsManager
    {
        // ── Singleton ───────────────────────────────────────────────
        private static AppSettingsManager _instance;
        public  static AppSettingsManager Instance =>
            _instance ?? (_instance = new AppSettingsManager());

        // ── File Paths ──────────────────────────────────────────────
        public static string AppDataRoot =>
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                         "Databranch", "ArnotOnboarding");

        public static string DraftsDirectory    => Path.Combine(AppDataRoot, "Drafts");
        public static string SettingsFilePath   => Path.Combine(AppDataRoot, "settings.json");
        public static string RequestorFilePath  => Path.Combine(AppDataRoot, "requestor.json");
        public static string CustomerFilePath   => Path.Combine(AppDataRoot, "customer-profile.json");
        public static string DraftIndexPath     => Path.Combine(AppDataRoot, "draft-index.json");
        public static string RecordIndexPath    => Path.Combine(AppDataRoot, "record-index.json");

        // ── Loaded Config Objects ───────────────────────────────────
        public AppSettings      Settings        { get; private set; }
        public RequestorProfile Requestor       { get; private set; }
        public CustomerProfile  Customer        { get; private set; }

        private readonly JsonSerializerSettings _jsonSettings = new JsonSerializerSettings
        {
            Formatting            = Formatting.Indented,
            NullValueHandling     = NullValueHandling.Include,
            DefaultValueHandling  = DefaultValueHandling.Include
        };

        private AppSettingsManager() { }

        // ── Initialization ──────────────────────────────────────────

        /// <summary>
        /// Ensures all required directories exist and loads all config files.
        /// Creates defaults if files do not exist. Call once at application startup.
        /// </summary>
        public void Initialize()
        {
            EnsureDirectories();
            Settings  = LoadOrCreate<AppSettings>(SettingsFilePath);
            Requestor = LoadOrCreate<RequestorProfile>(RequestorFilePath);
            Customer  = LoadOrCreate<CustomerProfile>(CustomerFilePath);
        }

        /// <summary>Creates all required %AppData% directories if they do not exist.</summary>
        private void EnsureDirectories()
        {
            Directory.CreateDirectory(AppDataRoot);
            Directory.CreateDirectory(DraftsDirectory);
        }

        // ── Load / Save Helpers ─────────────────────────────────────

        /// <summary>
        /// Loads a JSON config file and deserializes it. If the file does not exist,
        /// creates a new instance of T with default values and saves it immediately.
        /// </summary>
        private T LoadOrCreate<T>(string filePath) where T : new()
        {
            if (File.Exists(filePath))
            {
                try
                {
                    string json = File.ReadAllText(filePath);
                    return JsonConvert.DeserializeObject<T>(json, _jsonSettings) ?? new T();
                }
                catch (Exception ex)
                {
                    // If the file is corrupt, log and return defaults.
                    // A corrupt config should not crash the app.
                    System.Diagnostics.Debug.WriteLine($"[AppSettingsManager] Failed to load {filePath}: {ex.Message}");
                    var defaultObj = new T();
                    SaveJson(filePath, defaultObj);
                    return defaultObj;
                }
            }
            else
            {
                var defaultObj = new T();
                SaveJson(filePath, defaultObj);
                return defaultObj;
            }
        }

        /// <summary>Serializes an object and writes it to disk as formatted JSON.</summary>
        private void SaveJson<T>(string filePath, T obj)
        {
            try
            {
                string json = JsonConvert.SerializeObject(obj, _jsonSettings);
                File.WriteAllText(filePath, json);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[AppSettingsManager] Failed to save {filePath}: {ex.Message}");
                throw; // Re-throw — callers should handle save failures
            }
        }

        // ── Public Save Methods ─────────────────────────────────────

        public void SaveSettings()   => SaveJson(SettingsFilePath,  Settings);
        public void SaveRequestor()  => SaveJson(RequestorFilePath, Requestor);
        public void SaveCustomer()   => SaveJson(CustomerFilePath,  Customer);

        // ── Record Index ────────────────────────────────────────────

        public RecordIndex LoadRecordIndex()
            => LoadOrCreate<RecordIndex>(RecordIndexPath);

        public void SaveRecordIndex(RecordIndex index)
            => SaveJson(RecordIndexPath, index);

        // ── Draft Index ─────────────────────────────────────────────

        public DraftIndex LoadDraftIndex()
            => LoadOrCreate<DraftIndex>(DraftIndexPath);

        public void SaveDraftIndex(DraftIndex index)
            => SaveJson(DraftIndexPath, index);

        // ── Convenience: Serialize any object to JSON string ────────

        public string ToJson(object obj)
            => JsonConvert.SerializeObject(obj, _jsonSettings);

        public T FromJson<T>(string json)
            => JsonConvert.DeserializeObject<T>(json, _jsonSettings);
    }
}
