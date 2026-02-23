// SettingsView.cs — Phase 6 stub
using System.Windows.Forms;
using ArnotOnboarding.Theme;
namespace ArnotOnboarding.Views
{
    public partial class SettingsView : UserControl
    {
        public SettingsView() { InitializeComponent(); ThemeHelper.ApplyTheme(this); }
    }
}
