// =============================================================
// ArnotOnboarding — Page05_OtherAccounts.cs
// Version    : 1.3.2.0
// Changes    : - Column headers match form exactly:
//                Col 1 = Account Required, Col 2 = Admin Rights
//                under group header "Account/Admin Rights"
//                Cols 3-5 under shaded group header "Credentials Required"
//              - All named accounts with correct defaults
// =============================================================
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
using ArnotOnboarding.Models;
using ArnotOnboarding.Theme;

namespace ArnotOnboarding.Views.WizardPages
{
    public class Page05_OtherAccounts : WizardPageBase
    {
        public override string PageTitle => "Other Accounts (Step 9)";

        private struct AccountRow
        {
            public string   Name;
            public CheckBox ChkRequired, ChkAdmin, ChkInviteOnly, ChkMatchDomain, ChkMatchMS365;
            public bool     DefaultInviteOnly, DefaultMatchDomain, DefaultMatchMS365;
        }

        private readonly List<AccountRow> _rows = new List<AccountRow>();
        private TextBox  _txtOther1, _txtOther2, _txtOther3;
        private CheckBox _chkO1Req, _chkO1Adm, _chkO1Inv, _chkO1Dom, _chkO1MS;
        private CheckBox _chkO2Req, _chkO2Adm, _chkO2Inv, _chkO2Dom, _chkO2MS;
        private CheckBox _chkO3Req, _chkO3Adm, _chkO3Inv, _chkO3Dom, _chkO3MS;

        // Column X positions
        private const int C_NAME  = 24;    // Account name label
        private const int C_REQ   = 270;   // Account Required  ─┐ Account/Admin Rights group
        private const int C_ADM   = 340;   // Admin Rights      ─┘
        private const int C_INV   = 420;   // Invite Only       ─┐
        private const int C_DOM   = 490;   // Match Domain       │ Credentials Required group
        private const int C_MS    = 565;   // Match MS365       ─┘
        private const int CB_W    = 60;

        private static readonly (string Name, bool InvDef, bool DomDef, bool MsDef)[] ACCOUNTS = {
            ("Adobe Cloud (ARC)",               true,  false, false),
            ("Amazon (ARC) - Enforce 2FA",      true,  false, false),
            ("Appfolio (ARC)",                  true,  false, false),
            ("Autodesk (ARC)",                  true,  false, false),
            ("Breach Secure Now (IT)",          true,  false, false),
            ("Bosch Access Control (ARC)",      false, false, true),
            ("CoStar (ARC)",                    true,  false, false),
            ("DUO 2FA Security (IT)",           true,  true,  false),
            ("FileCloud (IT) - Enforce 2FA",    false, true,  false),
            ("Latch (ARC)",                     true,  false, false),
            ("LastPass (IT) - Enforce 2FA",     true,  false, false),
            ("Paycor (ARC)",                    false, false, true),
            ("RockIT VOIP (IT)",                true,  false, false),
            ("Sketchup (ARC)",                  true,  false, false),
            ("Vast 2 (IT)",                     false, false, true),
            ("VPN access (IT) – Duo required",  false, true,  false),
            ("WASP Inventory Cloud (ARC)",      true,  false, false),
            ("Zoom (ARC)",                      true,  false, false),
        };

        public Page05_OtherAccounts()
        {
            int y = START_Y;
            Controls.Add(MakeSectionHeader("Step 9 — Other Accounts Needed", y)); y += 30;

            // ── Group header row ──────────────────────────────────────
            // "Account/Admin Rights" spans cols 1-2; "Credentials Required" spans cols 3-5
            int ghY = y;

            // "Account/Admin Rights" — plain background band
            var lbAcctAdmin = new Label
            {
                Text      = "Account / Admin Rights",
                Location  = new Point(C_REQ - 4, ghY),
                Size      = new Size((C_ADM - C_REQ) + CB_W + 8, 18),
                Font      = AppFonts.Caption,
                ForeColor = AppColors.TextMuted,
                BackColor = Color.Transparent,
                TextAlign = ContentAlignment.MiddleLeft
            };
            Controls.Add(lbAcctAdmin);

            // "Credentials Required" — shaded background band
            var credsPanel = new Panel
            {
                Location  = new Point(C_INV - 6, ghY - 1),
                Size      = new Size((C_MS - C_INV) + CB_W + 10, 20),
                BackColor = AppColors.SurfaceCard
            };
            var lbCreds = new Label
            {
                Text      = "Credentials Required",
                Dock      = DockStyle.Fill,
                Font      = AppFonts.Caption,
                ForeColor = AppColors.TextMuted,
                BackColor = Color.Transparent,
                TextAlign = ContentAlignment.MiddleCenter
            };
            credsPanel.Controls.Add(lbCreds);
            Controls.Add(credsPanel);
            y += 22;

            // ── Column header row ─────────────────────────────────────
            AddColHdr("Account\nRequired", C_REQ, y);
            AddColHdr("Admin\nRights",     C_ADM, y);
            AddColHdr("Invite\nOnly",      C_INV, y);
            AddColHdr("Match\nDomain",     C_DOM, y);
            AddColHdr("Match\nMS365",      C_MS,  y);
            y += 34;

            Controls.Add(MakeDivider(y)); y += 8;

            // ── Named account rows ────────────────────────────────────
            foreach (var (name, invDef, domDef, msDef) in ACCOUNTS)
            {
                var row = new AccountRow
                {
                    Name = name,
                    DefaultInviteOnly  = invDef,
                    DefaultMatchDomain = domDef,
                    DefaultMatchMS365  = msDef
                };
                AddNamedRow(ref row, y);
                _rows.Add(row);
                y += 26;
            }

            Controls.Add(MakeDivider(y)); y += 8;

            // ── Other rows ────────────────────────────────────────────
            AddOtherRow(y, out _txtOther1, out _chkO1Req, out _chkO1Adm, out _chkO1Inv, out _chkO1Dom, out _chkO1MS); y += 26;
            AddOtherRow(y, out _txtOther2, out _chkO2Req, out _chkO2Adm, out _chkO2Inv, out _chkO2Dom, out _chkO2MS); y += 26;
            AddOtherRow(y, out _txtOther3, out _chkO3Req, out _chkO3Adm, out _chkO3Inv, out _chkO3Dom, out _chkO3MS);
        }

        private void AddColHdr(string text, int x, int y)
        {
            Controls.Add(new Label
            {
                Text      = text,
                Location  = new Point(x, y),
                Size      = new Size(CB_W, 32),
                Font      = AppFonts.Caption,
                ForeColor = AppColors.TextMuted,
                BackColor = Color.Transparent,
                TextAlign = ContentAlignment.BottomCenter
            });
        }

        private void AddNamedRow(ref AccountRow row, int y)
        {
            Controls.Add(new Label
            {
                Text         = row.Name,
                Location     = new Point(C_NAME, y + 3),
                Size         = new Size(C_REQ - C_NAME - 6, 20),
                Font         = AppFonts.BodySmall,
                ForeColor    = AppColors.TextSecondary,
                BackColor    = Color.Transparent,
                AutoEllipsis = true
            });
            row.ChkRequired   = AddCb(C_REQ, y, false);
            row.ChkAdmin      = AddCb(C_ADM, y, false);
            row.ChkInviteOnly = AddCb(C_INV, y, row.DefaultInviteOnly);
            row.ChkMatchDomain = AddCb(C_DOM, y, row.DefaultMatchDomain);
            row.ChkMatchMS365 = AddCb(C_MS,  y, row.DefaultMatchMS365);
        }

        private void AddOtherRow(int y,
            out TextBox txt,
            out CheckBox req, out CheckBox adm,
            out CheckBox inv, out CheckBox dom, out CheckBox ms)
        {
            Controls.Add(new Label { Text = "Other:", Location = new Point(C_NAME, y + 3), Size = new Size(42, 20), Font = AppFonts.BodySmall, ForeColor = AppColors.TextMuted, BackColor = Color.Transparent });
            txt = new TextBox
            {
                Location    = new Point(C_NAME + 46, y),
                Size        = new Size(C_REQ - C_NAME - 52, 20),
                BackColor   = AppColors.SurfaceVoid,
                ForeColor   = AppColors.TextPrimary,
                BorderStyle = BorderStyle.FixedSingle,
                Font        = AppFonts.BodySmall
            };
            txt.TextChanged += (s, e) => RaiseDataChanged();
            Controls.Add(txt);
            req = AddCb(C_REQ, y, false); adm = AddCb(C_ADM, y, false);
            inv = AddCb(C_INV, y, false); dom = AddCb(C_DOM, y, false); ms = AddCb(C_MS, y, false);
        }

        private CheckBox AddCb(int x, int y, bool def)
        {
            var cb = new CheckBox { Location = new Point(x + (CB_W - 16) / 2, y + 3), Size = new Size(18, 18), BackColor = Color.Transparent, Checked = def };
            cb.CheckedChanged += (s, e) => RaiseDataChanged();
            Controls.Add(cb);
            return cb;
        }

        public override void LoadData(OnboardingRecord r)
        {
            _loading = true;
            for (int i = 0; i < _rows.Count; i++)
            {
                var row = _rows[i];
                var st  = r.GetOtherAccountState(row.Name);
                row.ChkRequired.Checked    = st.AccountRequired;
                row.ChkAdmin.Checked       = st.AdminRights;
                row.ChkInviteOnly.Checked  = st.InviteOnly;
                row.ChkMatchDomain.Checked = st.MatchDomain;
                row.ChkMatchMS365.Checked  = st.MatchMS365;
                _rows[i] = row;
            }
            LoadOther(r.OtherAccount1, _txtOther1, _chkO1Req, _chkO1Adm, _chkO1Inv, _chkO1Dom, _chkO1MS);
            LoadOther(r.OtherAccount2, _txtOther2, _chkO2Req, _chkO2Adm, _chkO2Inv, _chkO2Dom, _chkO2MS);
            LoadOther(r.OtherAccount3, _txtOther3, _chkO3Req, _chkO3Adm, _chkO3Inv, _chkO3Dom, _chkO3MS);
            _loading = false;
        }

        private void LoadOther(OtherAccountState st, TextBox txt,
            CheckBox req, CheckBox adm, CheckBox inv, CheckBox dom, CheckBox ms)
        {
            txt.Text      = st?.Name ?? string.Empty;
            req.Checked   = st?.AccountRequired ?? false;
            adm.Checked   = st?.AdminRights     ?? false;
            inv.Checked   = st?.InviteOnly      ?? false;
            dom.Checked   = st?.MatchDomain     ?? false;
            ms.Checked    = st?.MatchMS365      ?? false;
        }

        public override OnboardingRecord SaveData(OnboardingRecord r)
        {
            foreach (var row in _rows)
                r.SetOtherAccountState(row.Name, new OtherAccountState
                {
                    Name            = row.Name,
                    AccountRequired = row.ChkRequired.Checked,
                    AdminRights     = row.ChkAdmin.Checked,
                    InviteOnly      = row.ChkInviteOnly.Checked,
                    MatchDomain     = row.ChkMatchDomain.Checked,
                    MatchMS365      = row.ChkMatchMS365.Checked
                });

            r.OtherAccount1 = SaveOther(_txtOther1, _chkO1Req, _chkO1Adm, _chkO1Inv, _chkO1Dom, _chkO1MS);
            r.OtherAccount2 = SaveOther(_txtOther2, _chkO2Req, _chkO2Adm, _chkO2Inv, _chkO2Dom, _chkO2MS);
            r.OtherAccount3 = SaveOther(_txtOther3, _chkO3Req, _chkO3Adm, _chkO3Inv, _chkO3Dom, _chkO3MS);
            return r;
        }

        private OtherAccountState SaveOther(TextBox txt,
            CheckBox req, CheckBox adm, CheckBox inv, CheckBox dom, CheckBox ms)
            => new OtherAccountState { Name = txt.Text.Trim(), AccountRequired = req.Checked, AdminRights = adm.Checked, InviteOnly = inv.Checked, MatchDomain = dom.Checked, MatchMS365 = ms.Checked };
    }
}
