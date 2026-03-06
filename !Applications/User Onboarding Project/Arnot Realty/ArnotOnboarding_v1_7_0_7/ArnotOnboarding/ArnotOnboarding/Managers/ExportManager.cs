// =============================================================
// ArnotOnboarding — ExportManager.cs
// Version    : 1.5.6.0
// Author     : Sam Kirsch
// Company    : Databranch
// Created    : 2026-02-27
// Modified   : 2026-02-28
// Description: Phase 4 — Finalization & Export
//              - Generates a PDF matching the Arnot Realty form layout
//                using MigraDoc / PdfSharp
//              - Saves a companion JSON data file
//              - Creates the employee directory on the HR network share
//              - Updates the local RecordIndex (past records)
//              - Removes the record from the draft index
//              - Opens Outlook compose window with PDF + JSON attached
//                (replaces mailto: with smart EML / COM interop routing)
//              - Detects Classic vs New Outlook via registry UserChoice
//                and routes to the best automation path automatically
//              - Requeries the HR share directory tree to pick up records
//                finalized by other users on different machines
//
// v1.5.4.0 — File naming convention updated:
//               PDF:  YYYYMMDD J Doe IT Onboard.pdf
//               JSON: YYYYMMDD J Doe IT Onboarding Data.json
//             Date used is record.CreatedAt (original request date), NOT
//             DateTime.Now — so a re-export/restart on a later day still
//             uses the original onboarding date, not today's date.
//
// v1.5.5.0 — RequeryNetworkShare now PRUNES index entries whose JSON
//             file no longer exists on disk before scanning for new ones.
//             Previously, manually deleted files stayed in the index
//             forever (only the PDF ✓/— column updated). Now a Refresh
//             gives a true authoritative view of what is actually on the
//             share. Also extracted DerivePdfPath() helper so the PDF
//             companion path is derived correctly for both old and new
//             filename formats (new format uses different stem for PDF
//             vs JSON, so Path.ChangeExtension was wrong for new files).
//
// v1.5.6.0 — Finalize now calls DraftManager.DeleteDraft instead of the
//             private RemoveFromDraftIndex helper. This ensures the .lock
//             sidecar file on the network share is released when a restarted
//             draft is exported. Previously the lock was never cleaned up,
//             allowing the same record to be restarted again immediately
//             (TryAcquire saw the stale lock as "our own" and re-used it).
// =============================================================

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using Microsoft.Win32;
using MigraDoc.DocumentObjectModel;
using MigraDoc.DocumentObjectModel.Tables;
using MigraDoc.Rendering;
using Newtonsoft.Json;
using ArnotOnboarding.Models;
using ArnotOnboarding.Utilities;

namespace ArnotOnboarding.Managers
{
    public class ExportResult
    {
        public bool   Success      { get; set; }
        public string PdfPath      { get; set; }
        public string JsonPath     { get; set; }
        public string EmployeeDir  { get; set; }
        public string ErrorMessage { get; set; }
    }

    public static class ExportManager
    {
        // ── Note ──────────────────────────────────────────────────────
        // HR path and email recipients are read from AppSettings (Settings page).
        // No hardcoded paths here — fully configurable at runtime.

        // ── Main entry point ─────────────────────────────────────────

        /// <summary>
        /// Finalizes a draft: generates PDF + JSON, saves to network share,
        /// updates RecordIndex, removes from DraftIndex.
        /// Returns an ExportResult with paths and success status.
        /// </summary>
        public static ExportResult Finalize(
            OnboardingRecord record,
            AppSettingsManager appSettings)
        {
            var result = new ExportResult();

            try
            {
                // ── 1. Build employee directory path ──────────────────
                // Format: {HrBasePath}\{LastName, FirstName}\{HrSubPath}
                var    settings  = appSettings.Settings;
                string lastName  = string.IsNullOrWhiteSpace(record.EmployeeLastName)
                    ? "Unknown" : record.EmployeeLastName.Trim();
                string firstName = string.IsNullOrWhiteSpace(record.EmployeeFirstName)
                    ? "Employee" : record.EmployeeFirstName.Trim();

                string empDir    = settings.BuildEmployeeExportPath(lastName, firstName);
                result.EmployeeDir = empDir;

                // Create directory if it doesn't exist (handles network share too)
                if (!Directory.Exists(empDir))
                    Directory.CreateDirectory(empDir);

                // ── 2. Build file names ───────────────────────────────
                // Date: always use CreatedAt (original request date) so a re-export
                // or restart on a different day keeps the same date in the filename.
                string datePrefix  = record.CreatedAt.ToString("yyyyMMdd");
                string firstInit   = PathHelper.MakeSafe(firstName.Length > 0 ? firstName[0].ToString() : "X");
                string lastSafe    = PathHelper.MakeSafe(lastName);
                string pdfName     = $"{datePrefix} {firstInit} {lastSafe} IT Onboard.pdf";
                string jsonName    = $"{datePrefix} {firstInit} {lastSafe} IT Onboarding Data.json";
                string pdfPath     = Path.Combine(empDir, pdfName);
                string jsonPath    = Path.Combine(empDir, jsonName);

                // ── 3. Generate PDF ────────────────────────────────────
                GeneratePdf(record, pdfPath);

                // ── 4. Save JSON ───────────────────────────────────────
                record.ExportedAt    = DateTime.Now;
                record.ExportPdfPath = pdfPath;
                record.ExportJsonPath = jsonPath;
                record.IsExported    = true;
                record.Status        = "finalized";

                string json = JsonConvert.SerializeObject(record, Formatting.Indented);
                File.WriteAllText(jsonPath, json, Encoding.UTF8);

                result.PdfPath  = pdfPath;
                result.JsonPath = jsonPath;

                // ── 5. Update local RecordIndex ────────────────────────
                AddToRecordIndex(record, appSettings);

                // ── 6. Remove draft and release any network lock ───────
                // Use DraftManager.DeleteDraft (not the private helper) so that
                // the .lock sidecar on the network share is released for records
                // that were created via Restart Onboarding. The SourceJsonPath
                // lives in the draft index entry — DeleteDraft reads it before
                // removing the entry.
                new DraftManager(appSettings).DeleteDraft(record.RecordId);

                // ── 7. Requery HR share for other users' records ───────
                RequeryNetworkShare(appSettings);

                result.Success = true;
            }
            catch (Exception ex)
            {
                result.Success      = false;
                result.ErrorMessage = ex.Message;
            }

            return result;
        }

        // ── PDF Generation ────────────────────────────────────────────

        private static void GeneratePdf(OnboardingRecord r, string outputPath)
        {
            var doc = new Document();
            doc.DefaultPageSetup.PageFormat     = PageFormat.Letter;
            doc.DefaultPageSetup.TopMargin      = Unit.FromInch(1.1);
            doc.DefaultPageSetup.BottomMargin   = Unit.FromInch(0.7);
            doc.DefaultPageSetup.LeftMargin     = Unit.FromInch(0.7);
            doc.DefaultPageSetup.RightMargin    = Unit.FromInch(0.7);
            doc.DefaultPageSetup.HeaderDistance = Unit.FromInch(0.35);
            doc.DefaultPageSetup.FooterDistance = Unit.FromInch(0.3);

            DefineStyles(doc);
            var section = doc.AddSection();

            // ── Page Header ───────────────────────────────────────────
            var hdr  = section.Headers.Primary;
            var hTbl = hdr.AddTable();
            hTbl.AddColumn(Unit.FromInch(4.5));
            hTbl.AddColumn(Unit.FromInch(2.8));
            var hRow = hTbl.AddRow();
            hRow.Cells[0].AddParagraph("Arnot Realty Corporation").Style = "FormHeader";
            hRow.Cells[0].AddParagraph("New User IT Request Form").Style = "FormSubHeader";
            hRow.Cells[1].VerticalAlignment = VerticalAlignment.Center;
            var gp = hRow.Cells[1].AddParagraph($"Generated: {DateTime.Now:MM/dd/yyyy h:mm tt}");
            gp.Style = "FieldNote"; gp.Format.Alignment = ParagraphAlignment.Right;
            hRow.Cells[1].AddParagraph($"Prepared by: {r.RequestorName ?? "Databranch"}").Style = "FieldNote";
            var div = hdr.AddParagraph();
            div.Format.Borders.Bottom = new Border { Width = 1.5, Color = Colors.DarkRed };
            div.Format.SpaceBefore = 4; div.Format.SpaceAfter = 6;

            // ── SECTION 1 — Request ───────────────────────────────────
            SH(section, "Section 1 — Request");
            var t1 = FT(section);
            TR(t1, "1a) Completed By",    FormatDate(r.CompletedByDate) + "  " + FormatTime(r.CompletedByTime));
            TR(t1, "1b) Setup Appointment", FormatDate(r.SetupAppointmentDate) + "  " + FormatTime(r.SetupAppointmentTime));

            // ── SECTION 2 — User Information ─────────────────────────
            SH(section, "Section 2 — User Information");
            var t2 = FT(section);
            TR(t2, "Employee Name",    r.FullName);
            TR(t2, "Email Address",    r.EmailAddress);
            TR(t2, "Work Phone",       r.WorkPhone + (string.IsNullOrEmpty(r.Extension) ? "" : $"  x{r.Extension}"));
            TR(t2, "Office Location",  r.OfficeLocation);
            TR(t2, "Title",            r.Title);
            TR(t2, "Department",       r.Department);
            TR(t2, "Computer Name",    r.PrimaryComputerName);

            // ── SECTION 3 — Requestor ─────────────────────────────────
            SH(section, "Section 3 — Requestor Information");
            var t3 = FT(section);
            TR(t3, "Requestor Name", r.RequestorName);
            TR(t3, "Email",          r.RequestorEmail);
            TR(t3, "Phone",          r.RequestorPhone + (string.IsNullOrEmpty(r.RequestorExtension) ? "" : $"  x{r.RequestorExtension}"));

            // ── STEPS 4-6 — Accounts ──────────────────────────────────
            SH(section, "Steps 4-6 — Accounts & Admin Rights");
            var t4 = FT(section);
            TCB(t4, "Step 4 — Accounts Needed",
                ("Domain (IT)", r.AccountDomain),
                ("MS365 / Email (IT) — Enforce 2FA", r.AccountMS365));
            TCB(t4, "Step 5 — MS365 License",
                ("Business Standard & Datto SaaS (Databranch setup)", r.LicenseBusinessStandard),
                ("Kiosk", r.LicenseKiosk));
            TRB(t4, "Step 6 — Local Admin Rights", r.LocalAdminRights, "Yes", "No");

            // ── STEPS 7-8 — Credentials ───────────────────────────────
            SH(section, "Steps 7-8 — Domain & MS365 Credentials");
            var t5 = FT(section);
            TR(t5, "7a) Domain Username",      r.DomainUsername);
            TR(t5, "7b) Domain Temp Password", r.DomainTempPassword);
            TRB(t5, "7c) Force password change at first login?", r.DomainForcePasswordChange, "Yes", "No");
            TR(t5, "8a) MS365 Username / Email", r.MS365Username);
            TR(t5, "8b) MS365 Temp Password",   r.MS365TempPassword);
            TRB(t5, "8c) Force password change at first login?", r.MS365ForcePasswordChange, "Yes", "No");
            TRB(t5, "8d) Run calendar access script?", r.RunCalendarScript, "Yes", "No");

            // ── STEP 9 — Other Accounts (full grid) ───────────────────
            SH(section, "Step 9 — Other Accounts");
            AddAccountsGrid(section, r);

            // ── STEPS 10-14 — Computer Setup ─────────────────────────
            SH(section, "Steps 10-14 — Computer Setup");
            var tc = FT(section);
            TRB(tc, "Step 10 — Computer type",    r.ComputerExisting, "Existing", "New");
            TRB(tc, "Step 11 — Factory reset?",   r.ResetToFactory, "Yes", "No");
            TR(tc,  "12) Computer name",           r.ExistingComputerName);
            TRB(tc, "12a) Rename computer?",       r.RenameComputer, "Yes", "No");
            if (r.RenameComputer)
                TR(tc, "12b) New name",            r.ComputerNewName);
            TRB(tc, "Step 13 — Relocate computer?", r.RelocateComputer, "Yes", "No");
            if (r.RelocateComputer)
            {
                TR(tc, "13a) Current location",   r.ComputerCurrentLocation);
                TR(tc, "13b) New location",        r.ComputerNewLocation);
            }
            TRB(tc, "Step 14 — Docking station required?", r.DockingStationRequired, "Yes", "No");
            if (r.DockingStationRequired)
            {
                TRB(tc, "14a) Compatible dock in user's location?", r.DockingCompatible, "Yes", "No");
                TRB(tc, "14b) Dock type",          r.DockTypeUSBC, "USB-C", "Other");
            }

            // ── STEPS 15-16 — Monitors & Applications ────────────────
            SH(section, "Steps 15-16 — Monitors & Applications");
            var tm = FT(section);
            TRB(tm, "Step 15 — Additional monitors?", r.AdditionalMonitors, "Yes", "No");
            if (r.AdditionalMonitors)
            {
                TR(tm, "15a) Monitor count", r.MonitorCount.ToString());
                TR(tm, "15b) Sizes needed",  r.MonitorSizes);
                AddMonitorGrid(section, r);
            }
            SH(section, "Step 16 — Applications to Set Up");
            AddAppGrid(section, r);

            // ── STEPS 17-20 — Print, Scan & Drives ───────────────────
            SH(section, "Steps 17-20 — Print, Scan & Drives");
            var tps = FT(section);
            TRB(tps, "Step 17 — Printers required?", r.PrintersRequired, "Yes", "No");
            if (r.PrintersRequired)
                TCB(tps, "  17a) Which printers?",
                    ("Main Office",  r.Printer17Main),
                    ("Stillwater",   r.Printer17Stillwater),
                    ("Ironworks",    r.Printer17Ironworks),
                    ("Other",        r.Printer17Other));
            TRB(tps, "Step 18 — Scan to folder?", r.ScanToFolder, "Yes", "No");
            if (r.ScanToFolder)
                TCB(tps, "  18a) Which scanners?",
                    ("Main Office",  r.Scanner18Main),
                    ("Stillwater",   r.Scanner18Stillwater),
                    ("Ironworks",    r.Scanner18Ironworks),
                    ("Other",        r.Scanner18Other));
            // 19 — drives
            TCB(tps, "Step 19 — Mapped Drives",
                ("R (All Office)", r.DriveR),
                ("Q (EX Office)",  r.DriveQ),
                ("K (UserData)",   r.DriveK),
                ("S (Scan)",       r.DriveS));
            // 20 — shared folders grid
            AddSharedFoldersGrid(section, r);

            // ── STEPS 21-25 — Email ───────────────────────────────────
            SH(section, "Steps 21-25 — Email");
            var te = FT(section);
            // Steps 21 & 22
            TRB(te, "Step 21 — Shared mailboxes?",   r.SharedMailboxes21,   "Yes", "No");
            if (r.SharedMailboxes21 && !string.IsNullOrWhiteSpace(r.SharedMailboxList))
                TR(te, "  21a) Mailboxes", r.SharedMailboxList);
            TRB(te, "Step 22 — Distribution lists?", r.DistributionLists22, "Yes", "No");
            if (r.DistributionLists22 && !string.IsNullOrWhiteSpace(r.DistributionListText))
                TR(te, "  22a) Lists", r.DistributionListText);
            // Steps 23 & 24 — Databranch engineer tasks (no user input)
            TR(te, "Step 23 — Databranch engineer", "Add employee + resource calendars (Small Conference, Board Room)");
            TR(te, "Step 24 — Databranch engineer", "Set up email signature");
            // Step 25
            TRB(te, "Step 25 — Email aliases?",      r.EmailAliases25,      "Yes", "No");
            if (r.EmailAliases25 && !string.IsNullOrWhiteSpace(r.EmailAliasesList))
                TR(te, "  25a) Aliases", r.EmailAliasesList);

            // ── STEPS 26-31 — Phone & Mobile ─────────────────────────
            SH(section, "Steps 26-31 — Office Phone & Mobile");
            var tp = FT(section);
            TRB(tp, "Step 26 — Office phone type", r.PhoneExisting, "Existing", "New");
            TRB(tp, "Step 27 — Relocate phone?",   r.PhoneRelocate, "Yes", "No");
            if (r.PhoneRelocate)
                TR(tp, "  27a) Current location", r.PhoneCurrentLocation);
            TRB(tp, "Step 28 — Extension change?", r.ExtensionChange, "Yes", "No");
            TR(tp, "Step 29 — Voicemail PIN",
                string.IsNullOrWhiteSpace(r.VmPin) ? "(not set)" : r.VmPin);
            TRB(tp, "Step 30 — Mobile phone issued?", r.PhoneIssued, "Yes", "No");
            if (r.PhoneIssued)
            {
                TR(tp, "  30a) Model",  r.PhoneModel);
                TR(tp, "  30a) Number", r.PhoneNumber);
                TRB(tp, "  30a) Device", r.PhoneDeviceExisting, "Existing", "New");
            }
            TRB(tp, "Step 30b — iPad issued?", r.iPadIssued, "Yes", "No");
            if (r.iPadIssued)
            {
                TR(tp, "  30b) Model",  r.iPadModel);
                TR(tp, "  30b) Number", r.iPadNumber);
                TRB(tp, "  30b) Device", r.iPadDeviceExisting, "Existing", "New");
            }
            TR(tp, "Step 31 — Databranch engineer", "Complete enrollment/assignment to Meraki MDM solution");

            // ── Notes ─────────────────────────────────────────────────
            SH(section, "Miscellaneous Notes");
            section.AddParagraph(
                string.IsNullOrWhiteSpace(r.MiscNotes) ? "(none)" : r.MiscNotes)
                .Style = "BodyText";

            // ── Footer ────────────────────────────────────────────────
            var footer = section.Footers.Primary;
            var fp = footer.AddParagraph();
            fp.Style = "FieldNote";
            fp.Format.Borders.Top = new Border { Width = 0.5, Color = Colors.Gray };
            fp.AddText($"Arnot Realty — IT Onboarding  |  {r.FullName}  |  " +
                       $"Finalized {r.ExportedAt:MM/dd/yyyy}  |  Databranch");
            fp.AddTab();
            fp.AddPageField();
            fp.Format.TabStops.AddTabStop(Unit.FromInch(7.3), TabAlignment.Right);

            var renderer = new PdfDocumentRenderer(true);
            renderer.Document = doc;
            renderer.RenderDocument();
            renderer.PdfDocument.Save(outputPath);
        }

        // ── Style definitions ─────────────────────────────────────────

        private static void DefineStyles(Document doc)
        {
            var normal = doc.Styles["Normal"];
            normal.Font.Name = "Arial";
            normal.Font.Size = 9;

            var fh = doc.Styles.AddStyle("FormHeader",    "Normal");
            fh.Font.Size = 13; fh.Font.Bold = true;
            fh.ParagraphFormat.SpaceAfter = 1;

            var fs = doc.Styles.AddStyle("FormSubHeader", "Normal");
            fs.Font.Size  = 9.5;
            fs.Font.Color = new Color(80, 80, 80);
            fs.ParagraphFormat.SpaceAfter = 2;

            var sh = doc.Styles.AddStyle("SectionHeader", "Normal");
            sh.Font.Bold  = true; sh.Font.Size = 9.5;
            sh.Font.Color = new Color(160, 20, 32);
            sh.ParagraphFormat.SpaceBefore = 8;
            sh.ParagraphFormat.SpaceAfter  = 2;
            sh.ParagraphFormat.Borders.Bottom =
                new Border { Width = 0.5, Color = new Color(200, 180, 180) };

            var fl = doc.Styles.AddStyle("FieldLabel", "Normal");
            fl.Font.Size  = 8.5;
            fl.Font.Color = new Color(90, 90, 90);

            var fv = doc.Styles.AddStyle("FieldValue", "Normal");
            fv.Font.Size  = 9;
            fv.Font.Color = Colors.Black;

            var fn = doc.Styles.AddStyle("FieldNote", "Normal");
            fn.Font.Size  = 7.5;
            fn.Font.Color = new Color(120, 120, 120);

            // CheckOn  = bold, dark — "[X]"  CheckOff = light grey — "[ ]"
            var ck = doc.Styles.AddStyle("CheckOn", "Normal");
            ck.Font.Size  = 9; ck.Font.Bold = true;
            ck.Font.Color = Colors.Black;

            var co = doc.Styles.AddStyle("CheckOff", "Normal");
            co.Font.Size  = 9; co.Font.Bold = false;
            co.Font.Color = new Color(160, 160, 160);

            var bt = doc.Styles.AddStyle("BodyText", "Normal");
            bt.Font.Size = 9;
            bt.ParagraphFormat.SpaceBefore = 3;
            bt.ParagraphFormat.SpaceAfter  = 3;
        }

        // ── Compact layout aliases ─────────────────────────────────────
        private static void SH(Section s, string t) { var p = s.AddParagraph(t); p.Style = "SectionHeader"; }

        // Standard two-column form table: 1.85" label | 5.45" value
        private static Table FT(Section s)
        {
            var t = s.AddTable();
            t.Borders.Width   = 0;
            t.Format.SpaceAfter = 0;
            t.AddColumn(Unit.FromInch(1.85));
            t.AddColumn(Unit.FromInch(5.45));
            return t;
        }

        // Text row
        private static void TR(Table t, string label, string value)
        {
            var row = t.AddRow();
            row.Height = Unit.FromPoint(14);
            row.Cells[0].AddParagraph(label).Style = "FieldLabel";
            row.Cells[1].AddParagraph(value ?? string.Empty).Style = "FieldValue";
            if (t.Rows.Count % 2 == 0) row.Shading.Color = new Color(248, 248, 248);
        }

        // Radio-button row: shows  ● Yes  ○ No  (or swapped)
        private static void TRB(Table t, string label, bool val, string trueLabel, string falseLabel)
        {
            var row = t.AddRow();
            row.Height = Unit.FromPoint(14);
            row.Cells[0].AddParagraph(label).Style = "FieldLabel";
            if (t.Rows.Count % 2 == 0) row.Shading.Color = new Color(248, 248, 248);

            // Build inline radio display in the value cell
            var p = row.Cells[1].AddParagraph();
            AppendRadio(p, trueLabel,  val);
            p.AddFormattedText("    ", "FieldValue");
            AppendRadio(p, falseLabel, !val);
        }

        private static void AppendRadio(Paragraph p, string label, bool selected)
        {
            // ● or ○
            string mark   = selected ? "\u25CF " : "\u25CB ";
            string style  = selected ? "CheckOn" : "CheckOff";
            p.AddFormattedText(mark + label + "  ", style);
        }

        // Checkbox row: shows  ☑ Opt1  ☐ Opt2  ☑ Opt3 ...
        private static void TCB(Table t, string label,
            params (string Label, bool Checked)[] options)
        {
            var row = t.AddRow();
            row.Height = Unit.FromPoint(14);
            row.Cells[0].AddParagraph(label).Style = "FieldLabel";
            if (t.Rows.Count % 2 == 0) row.Shading.Color = new Color(248, 248, 248);

            var p = row.Cells[1].AddParagraph();
            foreach (var (lbl, chk) in options)
            {
                string mark  = chk ? "[X] " : "[ ] ";
                string style = chk ? "CheckOn" : "CheckOff";
                p.AddFormattedText(mark + lbl + "   ", style);
            }
        }

        // ── Section-specific grid renderers ───────────────────────────

        // Step 9 — full accounts grid, all 18 named rows always shown
        private static void AddAccountsGrid(Section s, OnboardingRecord r)
        {
            var t = s.AddTable();
            t.Borders.Width = 0.25;
            t.Borders.Color = new Color(210, 210, 210);
            t.Format.SpaceAfter = 4;
            // Name | Acct Req | Admin | Invite | Match Dom | Match MS365
            t.AddColumn(Unit.FromInch(2.3));
            t.AddColumn(Unit.FromInch(0.72));
            t.AddColumn(Unit.FromInch(0.72));
            t.AddColumn(Unit.FromInch(0.72));
            t.AddColumn(Unit.FromInch(0.72));
            t.AddColumn(Unit.FromInch(0.72));
            t.AddColumn(Unit.FromInch(0.40)); // spacer

            // Group header
            var gh = t.AddRow(); gh.Height = Unit.FromPoint(12);
            gh.Shading.Color = new Color(235, 235, 235);
            gh.Cells[0].AddParagraph("").Style = "FieldNote";
            gh.Cells[1].MergeRight = 1;
            gh.Cells[1].AddParagraph("Account / Admin Rights").Style = "FieldNote";
            gh.Cells[1].Format.Alignment = ParagraphAlignment.Center;
            gh.Cells[3].MergeRight = 2;
            gh.Cells[3].AddParagraph("Credentials Required").Style = "FieldNote";
            gh.Cells[3].Format.Alignment = ParagraphAlignment.Center;
            gh.Cells[3].Shading.Color = new Color(225, 235, 248);

            // Column headers
            var ch = t.AddRow(); ch.Height = Unit.FromPoint(22);
            ch.Shading.Color = new Color(242, 242, 242);
            SetColHdr(ch.Cells[0], "Account");
            SetColHdr(ch.Cells[1], "Account\nRequired");
            SetColHdr(ch.Cells[2], "Admin\nRights");
            SetColHdr(ch.Cells[3], "Invite\nOnly");
            SetColHdr(ch.Cells[4], "Match\nDomain");
            SetColHdr(ch.Cells[5], "Match\nMS365");

            // All named account rows
            string[] names = {
                "Adobe Cloud (ARC)", "Amazon (ARC) - Enforce 2FA",
                "Appfolio (ARC)", "Autodesk (ARC)", "Breach Secure Now (IT)",
                "Bosch Access Control (ARC)", "CoStar (ARC)", "DUO 2FA Security (IT)",
                "FileCloud (IT) - Enforce 2FA", "Latch (ARC)", "LastPass (IT) - Enforce 2FA",
                "Paycor (ARC)", "RockIT VOIP (IT)", "Sketchup (ARC)",
                "Vast 2 (IT)", "VPN access (IT) - Duo required",
                "WASP Inventory Cloud (ARC)", "Zoom (ARC)"
            };

            int rowNum = 0;
            foreach (var name in names)
            {
                OtherAccountState st;
                if (!r.OtherAccounts.TryGetValue(name, out st))
                    st = new OtherAccountState { Name = name };

                var dr = t.AddRow();
                dr.Height = Unit.FromPoint(13);
                if (rowNum % 2 == 0) dr.Shading.Color = new Color(250, 250, 255);
                dr.Cells[0].AddParagraph(name).Style = "FieldNote";
                SetCheckCell(dr.Cells[1], st.AccountRequired);
                SetCheckCell(dr.Cells[2], st.AdminRights);
                SetCheckCell(dr.Cells[3], st.InviteOnly);
                SetCheckCell(dr.Cells[4], st.MatchDomain);
                SetCheckCell(dr.Cells[5], st.MatchMS365);
                for (int i = 1; i <= 5; i++)
                    dr.Cells[i].Format.Alignment = ParagraphAlignment.Center;
                rowNum++;
            }

            // Other rows
            foreach (var oth in new[] { r.OtherAccount1, r.OtherAccount2, r.OtherAccount3 })
            {
                if (oth == null || string.IsNullOrWhiteSpace(oth.Name)) continue;
                var dr = t.AddRow();
                dr.Height = Unit.FromPoint(13);
                if (rowNum % 2 == 0) dr.Shading.Color = new Color(250, 250, 255);
                dr.Cells[0].AddParagraph("Other: " + oth.Name).Style = "FieldNote";
                SetCheckCell(dr.Cells[1], oth.AccountRequired);
                SetCheckCell(dr.Cells[2], oth.AdminRights);
                SetCheckCell(dr.Cells[3], oth.InviteOnly);
                SetCheckCell(dr.Cells[4], oth.MatchDomain);
                SetCheckCell(dr.Cells[5], oth.MatchMS365);
                for (int i = 1; i <= 5; i++)
                    dr.Cells[i].Format.Alignment = ParagraphAlignment.Center;
                rowNum++;
            }
        }

        // Step 15b — monitor type grid (New / Existing radio per monitor)
        private static void AddMonitorGrid(Section s, OnboardingRecord r)
        {
            var t = s.AddTable();
            t.Borders.Width = 0.25;
            t.Borders.Color = new Color(210, 210, 210);
            t.Format.SpaceAfter = 4;
            t.AddColumn(Unit.FromInch(1.0));  // Monitor label
            t.AddColumn(Unit.FromInch(1.1));  // New / Existing
            t.AddColumn(Unit.FromInch(0.72)); // VGA
            t.AddColumn(Unit.FromInch(0.72)); // DVI
            t.AddColumn(Unit.FromInch(0.72)); // HDMI
            t.AddColumn(Unit.FromInch(0.72)); // DP

            var ch = t.AddRow(); ch.Height = Unit.FromPoint(13);
            ch.Shading.Color = new Color(242, 242, 242);
            SetColHdr(ch.Cells[0], "");
            SetColHdr(ch.Cells[1], "New / Existing");
            SetColHdr(ch.Cells[2], "Connector");
            SetColHdr(ch.Cells[3], "");
            SetColHdr(ch.Cells[4], "");
            SetColHdr(ch.Cells[5], "");

            AddMonitorRow(t, "Monitor 1", r.Monitor1New, r.Monitor1Existing, r.Monitor1Connector);
            AddMonitorRow(t, "Monitor 2", r.Monitor2New, r.Monitor2Existing, r.Monitor2Connector);
        }

        private static void AddMonitorRow(Table t, string label,
            bool isNew, bool isExisting, string connector)
        {
            var row = t.AddRow(); row.Height = Unit.FromPoint(14);
            row.Cells[0].AddParagraph(label).Style = "FieldNote";
            // Radio: New / Existing
            var p = row.Cells[1].AddParagraph();
            AppendRadio(p, "New",      isNew);
            p.AddFormattedText("  ", "FieldValue");
            AppendRadio(p, "Existing", isExisting);
            row.Cells[2].AddParagraph(connector ?? "VGA").Style = "FieldValue";
            // Cells 3-5 unused (was VGA/DVI/HDMI/DP bools — now single connector string)
            row.Cells[3].AddParagraph("").Style = "FieldValue";
            row.Cells[4].AddParagraph("").Style = "FieldValue";
            row.Cells[5].AddParagraph("").Style = "FieldValue";
            for (int i = 2; i <= 5; i++)
                row.Cells[i].Format.Alignment = ParagraphAlignment.Center;
        }

        // Step 16 — applications grid, 3 columns
        // Master app list — must match Page06b_MonitorsApps.APPS (nulls = column spacers, excluded here)
        private static readonly string[] WIZARD_APPS = {
            "Adobe Acrobat Pro",           "Google Earth",               "SNAPmobile (mobile)",
            "Adobe Acrobat Standard",      "iViewer (mobile)",           "Stamps.com",
            "Adobe Creative Suite",        "LastPass browser extension", "Vast2",
            "Adobe Acrobat Reader",        "Microsoft Office Suite",     "Zoom",
            "Appfolio (desktop & mobile)", "Revit LT",
            "AutoCAD LT",                  "Remote access to Doors PC",
            "Duo Security app (mobile)",   "SketchUp Pro",
        };

        private static void AddAppGrid(Section s, OnboardingRecord r)
        {
            // Start with the full wizard list, then append any extra checked apps not in it
            var allApps = new System.Collections.Generic.List<string>(WIZARD_APPS);
            var extra = r.Applications != null
                ? r.Applications.FindAll(a => !allApps.Contains(a))
                : new System.Collections.Generic.List<string>();
            var combined = new System.Collections.Generic.List<string>(allApps);
            combined.AddRange(extra);

            // 3-column grid
            var t = s.AddTable();
            t.Borders.Width = 0; t.Format.SpaceAfter = 4;
            t.AddColumn(Unit.FromInch(2.43));
            t.AddColumn(Unit.FromInch(2.43));
            t.AddColumn(Unit.FromInch(2.43));

            int perRow = 3;
            for (int i = 0; i < combined.Count; i += perRow)
            {
                var row = t.AddRow(); row.Height = Unit.FromPoint(14);
                if ((i / perRow) % 2 == 0) row.Shading.Color = new Color(248, 248, 248);
                for (int c = 0; c < perRow; c++)
                {
                    int idx = i + c;
                    if (idx >= combined.Count) break;
                    string app   = combined[idx];
                    bool   chk   = r.Applications != null && r.Applications.Contains(app);
                    string mark  = chk ? "[X] " : "[ ] ";
                    string style = chk ? "CheckOn" : "CheckOff";
                    row.Cells[c].AddParagraph(mark + app).Style = style;
                }
            }
            // Other text fields if populated
            if (!string.IsNullOrWhiteSpace(r.ApplicationOther1) ||
                !string.IsNullOrWhiteSpace(r.ApplicationOther2) ||
                !string.IsNullOrWhiteSpace(r.ApplicationOther3))
            {
                var ft = FT(s);
                if (!string.IsNullOrWhiteSpace(r.ApplicationOther1))
                    TR(ft, "  Other 1", r.ApplicationOther1);
                if (!string.IsNullOrWhiteSpace(r.ApplicationOther2))
                    TR(ft, "  Other 2", r.ApplicationOther2);
                if (!string.IsNullOrWhiteSpace(r.ApplicationOther3))
                    TR(ft, "  Other 3", r.ApplicationOther3);
            }
        }

        // Step 20 — shared folders grid
        private static void AddSharedFoldersGrid(Section s, OnboardingRecord r)
        {
            string[] folders = {
                "Development","Marketing","Leasing","Services","Operations",
                "Information Systems","Human Resources","Accounting","Finance","Shareholders"
            };
            var t = s.AddTable();
            t.Borders.Width = 0.25;
            t.Borders.Color = new Color(210, 210, 210);
            t.Format.SpaceAfter = 4;
            t.AddColumn(Unit.FromInch(3.5));
            t.AddColumn(Unit.FromInch(0.8));
            t.AddColumn(Unit.FromInch(0.8));

            var ch = t.AddRow(); ch.Height = Unit.FromPoint(13);
            ch.Shading.Color = new Color(242, 242, 242);
            SetColHdr(ch.Cells[0], "Step 20 — Shared Folder");
            SetColHdr(ch.Cells[1], "R:\\");
            SetColHdr(ch.Cells[2], "Q:\\");
            ch.Cells[1].Format.Alignment = ParagraphAlignment.Center;
            ch.Cells[2].Format.Alignment = ParagraphAlignment.Center;

            for (int i = 0; i < folders.Length; i++)
            {
                bool rChk = r.SharedFolderR != null && r.SharedFolderR.Contains(folders[i]);
                bool qChk = r.SharedFolderQ != null && r.SharedFolderQ.Contains(folders[i]);
                var row = t.AddRow(); row.Height = Unit.FromPoint(13);
                if (i % 2 == 0) row.Shading.Color = new Color(250, 250, 255);
                row.Cells[0].AddParagraph(folders[i]).Style = "FieldNote";
                SetCheckCell(row.Cells[1], rChk);
                SetCheckCell(row.Cells[2], qChk);
                row.Cells[1].Format.Alignment = ParagraphAlignment.Center;
                row.Cells[2].Format.Alignment = ParagraphAlignment.Center;
            }
        }

        // ── Cell helpers ──────────────────────────────────────────────

        private static void SetColHdr(Cell c, string text)
        {
            var p = c.AddParagraph(text); p.Style = "FieldNote";
            p.Format.Alignment = ParagraphAlignment.Center;
        }

        private static void SetCheckCell(Cell c, bool chk)
        {
            string mark  = chk ? "[X]" : "[ ]";
            string style = chk ? "CheckOn" : "CheckOff";
            c.AddParagraph(mark).Style = style;
        }

        // ── Value formatting helpers ──────────────────────────────────
        private static string YesNo(bool v)            => v ? "Yes" : "No";
        private static string Tick(bool v)             => v ? "[X]" : "[ ]";
        private static string FormatDate(DateTime? d)  => d?.ToString("MM/dd/yyyy") ?? "";
        private static string FormatTime(TimeSpan? t2) => t2.HasValue
            ? DateTime.Today.Add(t2.Value).ToString("h:mm tt") : "";

        private static string Checks(params (string Label, bool Checked)[] items)
        {
            var parts = System.Linq.Enumerable.Where(items, i => i.Checked)
                              .Select(i => i.Label);
            return string.Join(",  ", parts);
        }
        private static string PrinterList(OnboardingRecord r)
        {
            var l = new System.Collections.Generic.List<string>();
            if (r.Printer17Main)       l.Add("Main Office");
            if (r.Printer17Stillwater) l.Add("Stillwater");
            if (r.Printer17Ironworks)  l.Add("Ironworks");
            if (r.Printer17Other)      l.Add("Other");
            return string.Join(", ", l);
        }
        private static string ScannerList(OnboardingRecord r)
        {
            var l = new System.Collections.Generic.List<string>();
            if (r.Scanner18Main)       l.Add("Main Office");
            if (r.Scanner18Stillwater) l.Add("Stillwater");
            if (r.Scanner18Ironworks)  l.Add("Ironworks");
            if (r.Scanner18Other)      l.Add("Other");
            return string.Join(", ", l);
        }
        private static string DriveList(OnboardingRecord r)
        {
            var l = new System.Collections.Generic.List<string>();
            if (r.DriveR) l.Add("R (All Office)");
            if (r.DriveQ) l.Add("Q (EX Office)");
            if (r.DriveK) l.Add("K (UserData)");
            if (r.DriveS) l.Add("S (Scan)");
            return l.Count > 0 ? string.Join(", ", l) : "(none)";
        }
        private static string FormatSharedFolders(OnboardingRecord r)
        {
            var sb = new System.Text.StringBuilder();
            if (r.SharedFolderR?.Count > 0)
                sb.Append("R:\\  " + string.Join(", ", r.SharedFolderR) + "  ");
            if (r.SharedFolderQ?.Count > 0)
                sb.Append("Q:\\  " + string.Join(", ", r.SharedFolderQ));
            return sb.ToString().Trim();
        }

        // ── Index management ─────────────────────────────────────────

        private static void AddToRecordIndex(
            OnboardingRecord record, AppSettingsManager appSettings)
        {
            var index = appSettings.LoadRecordIndex();

            // Deduplicate on THREE signals so re-exporting the same employee
            // never creates another row:
            //   1. Exact RecordId match (same export session / same draft GUID)
            //   2. Same PDF output path (re-exporting overwrites the file)
            //   3. Same employee name + same date (same day re-export)
            string empName  = $"{record.EmployeeLastName}, {record.EmployeeFirstName}";
            string pdfPath  = record.ExportPdfPath ?? string.Empty;
            string dateStr  = (record.ExportedAt ?? DateTime.Now).ToString("yyyy-MM-dd");

            index.Entries.RemoveAll(e =>
                e.RecordId == record.RecordId ||
                (!string.IsNullOrEmpty(pdfPath) &&
                 string.Equals(e.PdfPath, pdfPath, StringComparison.OrdinalIgnoreCase)) ||
                (string.Equals(e.EmployeeName, empName, StringComparison.OrdinalIgnoreCase) &&
                 e.FinalizedAt.ToString("yyyy-MM-dd") == dateStr));

            index.Entries.Add(new RecordIndexEntry
            {
                RecordId       = record.RecordId,
                EmployeeName   = empName,
                Department     = record.Department,
                FinalizedAt    = record.ExportedAt ?? DateTime.Now,
                JsonPath       = record.ExportJsonPath,
                PdfPath        = record.ExportPdfPath,
                LastVerified   = true,
                LastVerifiedAt = DateTime.Now
            });

            // Sort: most recently finalized first
            index.Entries.Sort((a, b) =>
                b.FinalizedAt.CompareTo(a.FinalizedAt));

            appSettings.SaveRecordIndex(index);
        }

        // ── Network share requery ─────────────────────────────────────

        /// <summary>
        /// Scans R:\66 Human Resources Q\666 Employee Files\ for subdirectories
        /// in "LastName, FirstName" format containing OnboardingRecord JSON files.
        /// Any finalized records not already in the local index are added.
        /// This picks up records created by other Databranch engineers on
        /// different machines.
        /// </summary>
        public static void RequeryNetworkShare(AppSettingsManager appSettings)
        {
            string basePath = appSettings.Settings.HrBasePath;
            string subPath  = appSettings.Settings.HrSubPath.TrimStart('\\').TrimStart('/');
            if (!Directory.Exists(basePath)) return;

            var index = appSettings.LoadRecordIndex();

            // ── Step 1: Prune index entries whose JSON no longer exists on disk ──
            // This handles manually deleted files and the "duplicate on a different
            // day" case — if the JSON is gone, the record is gone.
            int beforeCount = index.Entries.Count;
            index.Entries.RemoveAll(e =>
                !string.IsNullOrEmpty(e.JsonPath) && !File.Exists(e.JsonPath));
            bool pruned = index.Entries.Count < beforeCount;

            // ── Step 2: Build lookup sets for duplicate detection ────────────────
            var existingByRecordId = new Dictionary<string, RecordIndexEntry>(
                StringComparer.OrdinalIgnoreCase);
            var existingByJsonPath = new Dictionary<string, RecordIndexEntry>(
                StringComparer.OrdinalIgnoreCase);

            foreach (var e in index.Entries)
            {
                if (!string.IsNullOrEmpty(e.RecordId))
                    existingByRecordId[e.RecordId] = e;
                if (!string.IsNullOrEmpty(e.JsonPath))
                    existingByJsonPath[e.JsonPath]  = e;
            }

            bool changed = pruned;

            // ── Step 3: Scan network share for new/moved records ─────────────────
            try
            {
                foreach (string empDir in Directory.GetDirectories(basePath))
                {
                    string searchDir = Path.Combine(empDir, subPath);
                    if (!Directory.Exists(searchDir)) continue;

                    // Match both naming conventions:
                    //   New: "20260228 J Doe IT Onboarding Data.json"
                    //   Old: "Doe_Jane_Onboarding_2026-02-28.json"
                    var jsonFiles = new List<string>();
                    jsonFiles.AddRange(Directory.GetFiles(searchDir, "* IT Onboarding Data.json"));
                    jsonFiles.AddRange(Directory.GetFiles(searchDir, "*_Onboarding_*.json"));

                    foreach (string jsonFile in jsonFiles)
                    {
                        try
                        {
                            // Skip files whose path is already tracked
                            if (existingByJsonPath.ContainsKey(jsonFile)) continue;

                            string text = File.ReadAllText(jsonFile, Encoding.UTF8);
                            var rec = JsonConvert.DeserializeObject<OnboardingRecord>(text);
                            if (rec == null || rec.Status != "finalized") continue;

                            // Derive the companion PDF path.
                            // New format: "YYYYMMDD J Doe IT Onboarding Data.json"
                            //          → "YYYYMMDD J Doe IT Onboard.pdf"
                            // Old format: "Doe_Jane_Onboarding_2026-02-28.json"
                            //          → "Doe_Jane_Onboarding_2026-02-28.pdf"
                            string pdfPath = DerivePdfPath(jsonFile);

                            // If the same RecordId is already in the index (e.g. added
                            // locally then found again on network), update paths only.
                            if (existingByRecordId.TryGetValue(rec.RecordId, out var existing))
                            {
                                existing.JsonPath       = jsonFile;
                                existing.PdfPath        = pdfPath;
                                existing.LastVerified   = true;
                                existing.LastVerifiedAt = DateTime.Now;
                                existingByJsonPath[jsonFile] = existing;
                                changed = true;
                                continue;
                            }

                            var entry = new RecordIndexEntry
                            {
                                RecordId       = rec.RecordId,
                                EmployeeName   = $"{rec.EmployeeLastName}, {rec.EmployeeFirstName}",
                                Department     = rec.Department,
                                FinalizedAt    = rec.ExportedAt ?? rec.LastModified,
                                JsonPath       = jsonFile,
                                PdfPath        = pdfPath,
                                LastVerified   = true,
                                LastVerifiedAt = DateTime.Now
                            };
                            index.Entries.Add(entry);
                            existingByRecordId[rec.RecordId] = entry;
                            existingByJsonPath[jsonFile]     = entry;
                            changed = true;
                        }
                        catch { /* skip malformed or unreadable files */ }
                    }
                }
            }
            catch { /* network unreachable — silent fail, don't block export */ }

            // ── Step 4: Persist if anything changed ──────────────────────────────
            if (changed)
            {
                index.Entries.Sort((a, b) =>
                    b.FinalizedAt.CompareTo(a.FinalizedAt));
                appSettings.SaveRecordIndex(index);
            }
        }

        /// <summary>
        /// Derives the companion PDF path from a JSON path, handling both
        /// the new filename format and the legacy format.
        ///
        /// New: "20260228 J Doe IT Onboarding Data.json"
        ///   → "20260228 J Doe IT Onboard.pdf"
        /// Old: "Doe_Jane_Onboarding_2026-02-28.json"
        ///   → "Doe_Jane_Onboarding_2026-02-28.pdf"
        /// </summary>
        private static string DerivePdfPath(string jsonPath)
        {
            string dir      = Path.GetDirectoryName(jsonPath);
            string jsonName = Path.GetFileNameWithoutExtension(jsonPath);

            // New format ends with " IT Onboarding Data"
            const string newSuffix = " IT Onboarding Data";
            if (jsonName.EndsWith(newSuffix, StringComparison.OrdinalIgnoreCase))
            {
                string stem    = jsonName.Substring(0, jsonName.Length - newSuffix.Length);
                string pdfName = stem + " IT Onboard.pdf";
                return Path.Combine(dir, pdfName);
            }

            // Old format: simple extension swap
            return Path.ChangeExtension(jsonPath, ".pdf");
        }

        // ── Outlook email (with attachments) ─────────────────────────

        // Registry key Windows uses to track the user's default mailto handler.
        private const string MailtoUserChoiceKey =
            @"Software\Microsoft\Windows\Shell\Associations\UrlAssociations\MAILTO\UserChoice";

        /// <summary>
        /// Detects whether Classic Outlook is the user's default mailto handler
        /// by reading HKCU\...\MAILTO\UserChoice\ProgId from the registry.
        /// Classic Outlook registers a ProgId starting with "Outlook.URL.mailto".
        /// New Outlook (AppX/Store) registers a ProgId starting with "AppX".
        /// </summary>
        private static bool IsClassicOutlookDefault()
        {
            try
            {
                using (var key = Registry.CurrentUser.OpenSubKey(MailtoUserChoiceKey, false))
                {
                    var progId = key?.GetValue("ProgId") as string;
                    return !string.IsNullOrWhiteSpace(progId) &&
                           progId.StartsWith("Outlook.URL.mailto",
                               StringComparison.OrdinalIgnoreCase);
                }
            }
            catch
            {
                return false; // Fallback to EML path on any registry error
            }
        }

        /// <summary>
        /// Opens a new Outlook compose window pre-populated with To/CC/Subject/Body
        /// and with the PDF and JSON files already attached.
        ///
        /// Routing logic:
        ///   Classic Outlook (default) → COM Interop (MailItem.Display)
        ///   New Outlook / unknown     → RFC-822 .eml with X-Unsent:1 via Process.Start
        ///
        /// Both paths open an editable compose window — the user reviews and sends.
        /// No email is sent automatically.
        /// </summary>
        public static void OpenOutlookEmail(
            OnboardingRecord record,
            string pdfPath,
            AppSettingsManager appSettings = null)
        {
            var    s      = appSettings?.Settings ?? AppSettingsManager.Instance.Settings;
            string to     = string.IsNullOrWhiteSpace(s.NotifyEmail1)
                ? "support@databranch.com" : s.NotifyEmail1;
            string cc     = string.IsNullOrWhiteSpace(s.NotifyEmail2)
                ? "help@databranch.com"    : s.NotifyEmail2;
            string subject = $"Arnot Realty - New Employee Onboarding Form - " +
                             $"{record.EmployeeFirstName} {record.EmployeeLastName}";
            string body    = BuildEmailBody(record, pdfPath);

            // Collect attachment paths (only files that actually exist)
            var attachments = new List<string>();
            if (!string.IsNullOrWhiteSpace(pdfPath)  && File.Exists(pdfPath))
                attachments.Add(pdfPath);
            if (!string.IsNullOrWhiteSpace(record.ExportJsonPath) &&
                File.Exists(record.ExportJsonPath))
                attachments.Add(record.ExportJsonPath);

            bool usedInterop = false;

            // ── Path A: Classic Outlook via COM Interop ───────────────
            if (IsClassicOutlookDefault())
            {
                try
                {
                    ComposeViaInterop(to, cc, subject, body, attachments);
                    usedInterop = true;
                }
                catch
                {
                    // COM failed (e.g. bitness mismatch, security prompt blocked) —
                    // fall through silently to the EML path.
                    usedInterop = false;
                }
            }

            // ── Path B: EML file (New Outlook + Classic fallback) ─────
            if (!usedInterop)
            {
                ComposeViaEml(to, cc, subject, body, attachments);
            }
        }

        // ── Path A: Classic Outlook COM Interop ───────────────────────

        /// <summary>
        /// Uses late-bound COM (no compile-time reference to Interop.Outlook)
        /// so the project does not need Microsoft.Office.Interop.Outlook.dll.
        /// Works with any installed Office version (2016 / 2019 / 2021 / LTSC).
        /// </summary>
        private static void ComposeViaInterop(
            string to, string cc, string subject, string body,
            IList<string> attachmentPaths)
        {
            // Late-bind via pure reflection -- no Microsoft.CSharp / dynamic required,
            // and no compile-time reference to Microsoft.Office.Interop.Outlook.dll.
            Type outlookType = Type.GetTypeFromProgID("Outlook.Application");
            if (outlookType == null)
                throw new InvalidOperationException("Outlook.Application ProgID not found.");

            object app;
            try
            {
                // Prefer an already-running Outlook instance
                app = System.Runtime.InteropServices.Marshal.GetActiveObject("Outlook.Application");
            }
            catch
            {
                app = Activator.CreateInstance(outlookType);
            }

            // app.CreateItem(0)  -- olMailItem = 0
            object mail = outlookType.InvokeMember(
                "CreateItem",
                System.Reflection.BindingFlags.InvokeMethod,
                null, app,
                new object[] { 0 });

            Type mailType = mail.GetType();

            // Set simple string properties
            mailType.InvokeMember("To",      System.Reflection.BindingFlags.SetProperty, null, mail, new object[] { to });
            mailType.InvokeMember("CC",      System.Reflection.BindingFlags.SetProperty, null, mail, new object[] { cc });
            mailType.InvokeMember("Subject", System.Reflection.BindingFlags.SetProperty, null, mail, new object[] { subject });
            mailType.InvokeMember("Body",    System.Reflection.BindingFlags.SetProperty, null, mail, new object[] { body });

            // mail.Attachments  (returns the Attachments collection object)
            object attachments = mailType.InvokeMember(
                "Attachments",
                System.Reflection.BindingFlags.GetProperty,
                null, mail, null);

            Type attachType = attachments.GetType();

            // attachments.Add(path, olByValue=1, Position=missing, DisplayName=missing)
            foreach (string path in attachmentPaths)
            {
                attachType.InvokeMember(
                    "Add",
                    System.Reflection.BindingFlags.InvokeMethod,
                    null, attachments,
                    new object[] { path, 1, Type.Missing, Type.Missing });
            }

            // mail.Display(false)  -- non-modal compose window
            mailType.InvokeMember(
                "Display",
                System.Reflection.BindingFlags.InvokeMethod,
                null, mail,
                new object[] { false });
        }

        // ── Path B: RFC-822 .eml with MIME attachments ────────────────

        /// <summary>
        /// Builds a standards-compliant multipart/mixed .eml file in memory,
        /// writes it to %TEMP%, and opens it with Process.Start(UseShellExecute).
        ///
        /// Both Classic Outlook and New Outlook are registered as .eml handlers
        /// and open the file in compose mode when the X-Unsent: 1 header is present.
        ///
        /// Uses only BCL types (System.Text, System.IO, System.Convert) — no
        /// additional NuGet packages required.
        /// </summary>
        private static void ComposeViaEml(
            string to, string cc, string subject, string body,
            IList<string> attachmentPaths)
        {
            const string boundary = "----=_ArnotOnboarding_MIME_Boundary_v1";
            var sb = new StringBuilder();

            // ── RFC-822 / MIME headers ────────────────────────────────
            sb.AppendLine("MIME-Version: 1.0");
            sb.AppendLine($"To: {to}");
            sb.AppendLine($"CC: {cc}");
            sb.AppendLine($"Subject: {subject}");
            sb.AppendLine("X-Unsent: 1");           // Critical: tells Outlook to open in compose mode
            sb.AppendLine($"Content-Type: multipart/mixed; boundary=\"{boundary}\"");
            sb.AppendLine();

            // ── Plain-text body part ─────────────────────────────────
            sb.AppendLine($"--{boundary}");
            sb.AppendLine("Content-Type: text/plain; charset=utf-8");
            sb.AppendLine("Content-Transfer-Encoding: quoted-printable");
            sb.AppendLine();
            sb.AppendLine(EncodeQuotedPrintable(body));
            sb.AppendLine();

            // ── Attachment parts ──────────────────────────────────────
            foreach (string path in attachmentPaths)
            {
                string fileName  = Path.GetFileName(path);
                string mimeType  = GetMimeType(fileName);
                byte[] fileBytes = File.ReadAllBytes(path);
                string base64    = Convert.ToBase64String(fileBytes);

                sb.AppendLine($"--{boundary}");
                sb.AppendLine($"Content-Type: {mimeType}; name=\"{fileName}\"");
                sb.AppendLine("Content-Transfer-Encoding: base64");
                sb.AppendLine($"Content-Disposition: attachment; filename=\"{fileName}\"");
                sb.AppendLine();

                // Write base64 in 76-char lines (RFC 2045 requirement)
                for (int i = 0; i < base64.Length; i += 76)
                    sb.AppendLine(base64.Substring(i, Math.Min(76, base64.Length - i)));

                sb.AppendLine();
            }

            // ── Closing boundary ──────────────────────────────────────
            sb.AppendLine($"--{boundary}--");

            // ── Write to temp and launch ──────────────────────────────
            string emlPath = Path.Combine(
                Path.GetTempPath(),
                $"ArnotOnboarding_{Guid.NewGuid():N}.eml");

            File.WriteAllText(emlPath, sb.ToString(), Encoding.UTF8);

            Process.Start(new ProcessStartInfo
            {
                FileName        = emlPath,
                UseShellExecute = true   // Let Windows route to the registered .eml handler
            });
        }

        /// <summary>
        /// Returns the MIME content type for common file extensions.
        /// </summary>
        private static string GetMimeType(string fileName)
        {
            string ext = Path.GetExtension(fileName)?.ToLowerInvariant() ?? "";
            switch (ext)
            {
                case ".pdf":  return "application/pdf";
                case ".json": return "application/json";
                case ".txt":  return "text/plain";
                case ".png":  return "image/png";
                case ".jpg":
                case ".jpeg": return "image/jpeg";
                case ".docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
                case ".xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
                default:      return "application/octet-stream";
            }
        }

        /// <summary>
        /// Encodes a plain-text string using Quoted-Printable (RFC 2045).
        /// Handles non-ASCII characters and long lines so the body renders
        /// correctly in all Outlook versions.
        /// </summary>
        private static string EncodeQuotedPrintable(string input)
        {
            if (string.IsNullOrEmpty(input)) return string.Empty;

            var sb     = new StringBuilder();
            int lineLen = 0;

            foreach (char c in input)
            {
                if (c == '\r') continue;  // strip bare CR; we'll add CRLF on \n

                if (c == '\n')
                {
                    sb.AppendLine();
                    lineLen = 0;
                    continue;
                }

                // Characters that must be encoded
                bool encode = (c > 126) || (c < 32 && c != '\t') || c == '=';

                string token;
                if (encode)
                    token = $"={((int)c):X2}";
                else
                    token = c.ToString();

                // Soft line break at 75 chars (76 with the = continuation)
                if (lineLen + token.Length > 75)
                {
                    sb.AppendLine("=");
                    lineLen = 0;
                }

                sb.Append(token);
                lineLen += token.Length;
            }

            return sb.ToString();
        }

        // ── Email body builder ────────────────────────────────────────

        private static string BuildEmailBody(OnboardingRecord r, string pdfPath)
        {
            string jsonPath = r.ExportJsonPath ?? string.Empty;
            string folder   = string.IsNullOrWhiteSpace(pdfPath)
                ? string.Empty
                : Path.GetDirectoryName(pdfPath);

            var sb = new StringBuilder();
            sb.AppendLine("Hello,");
            sb.AppendLine();
            sb.AppendLine($"A new employee onboarding form has been completed for {r.FullName}.");
            sb.AppendLine();
            sb.AppendLine("EMPLOYEE DETAILS");
            sb.AppendLine($"  Name:         {r.FullName}");
            sb.AppendLine($"  Title:        {r.Title}");
            sb.AppendLine($"  Department:   {r.Department}");
            sb.AppendLine($"  Email:        {r.EmailAddress}");
            sb.AppendLine($"  Domain User:  {r.DomainUsername}");
            sb.AppendLine($"  Requestor:    {r.RequestorName}" +
                (string.IsNullOrWhiteSpace(r.RequestorEmail) ? "" : $" ({r.RequestorEmail})"));
            sb.AppendLine();
            sb.AppendLine("FILES — saved to HR network share");
            sb.AppendLine($"  Folder:  {folder}");
            sb.AppendLine($"  PDF:     {pdfPath}");
            sb.AppendLine($"  JSON:    {jsonPath}");
            sb.AppendLine();
            sb.AppendLine("Please review and action as appropriate.");
            sb.AppendLine();
            sb.AppendLine("---");
            sb.AppendLine("Generated by the Arnot Realty Onboarding App — Databranch");
            return sb.ToString();
        }

    }
}
