using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Threading;
using StudyManagerFC.Core;

namespace StudyManagerFC.Desktop;

public enum MainSection
{
    Dashboard,
    StudyLog,
    Subjects,
    Squad,
    Transfers,
    Europe
}

public interface IPage
{
    Control View { get; }
    void Refresh();
}

public class MainWindow : Window
{
    public GameStore Store { get; }

    private readonly ContentControl _host = new();
    private readonly DispatcherTimer _timer;
    private readonly Dictionary<MainSection, IPage> _pages = [];
    private readonly List<(MainSection Section, ActionButton Button)> _tabs = [];
    private ActionButton _resetButton = null!;
    private TextBlock _seasonLabel = null!;
    private TextBlock _cashLabel = null!;
    private IPage? _page;
    private bool _lastHasCareer;
    private MainSection _section = MainSection.Dashboard;

    public MainWindow(GameStore store)
    {
        Store = store;
        Title = "StudyManager FC";
        Width = 1300;
        Height = 860;
        MinWidth = 1080;
        MinHeight = 720;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = AppBackground.Brush;

        _lastHasCareer = store.HasCareer;
        Content = BuildRoot();
        Store.Changed += OnStoreChanged;

        _timer = new DispatcherTimer(TimeSpan.FromSeconds(1), DispatcherPriority.Background, (_, _) =>
        {
            if (Store.IsTimerRunning) Store.TimerTick();
        });
        _timer.Start();
    }

    private Control BuildRoot()
    {
        if (!Store.HasCareer)
        {
            _page = null;
            return new ClubSelectionView(Store, this).View;
        }

        _tabs.Clear();
        var tabs = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
        foreach (var section in Enum.GetValues<MainSection>())
        {
            var button = new ActionButton(
                SectionTitle(section),
                Colors.Transparent,
                Palette.Secondary,
                radius: 999,
                padding: new Thickness(14, 7),
                fontSize: 12);
            var captured = section;
            button.Clicked += () => Navigate(captured);
            _tabs.Add((section, button));
            tabs.Children.Add(button);
        }

        _seasonLabel = Ui.Secondary("", 10);
        _cashLabel = Ui.Text("", 12, FontWeight.Bold, Ui.Brush(Palette.Gold));
        _resetButton = new ActionButton(
            "↺  Reset",
            Colors.Transparent,
            Palette.Secondary,
            radius: 999,
            padding: new Thickness(12, 6),
            fontSize: 11);
        _resetButton.Clicked += ShowResetDialog;

        var right = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 12,
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center
        };
        var status = new StackPanel
        {
            Spacing = 1,
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Right
        };
        _seasonLabel.HorizontalAlignment = HorizontalAlignment.Right;
        _cashLabel.HorizontalAlignment = HorizontalAlignment.Right;
        status.Children.Add(_seasonLabel);
        status.Children.Add(_cashLabel);
        right.Children.Add(status);
        right.Children.Add(_resetButton);

        var header = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*,Auto") };
        header.Children.Add(tabs);
        Grid.SetColumn(right, 2);
        header.Children.Add(right);

        var headerBorder = new Border
        {
            Padding = new Thickness(22, 12),
            Child = header,
            Background = Ui.Brush(Color.FromArgb(150, 255, 255, 255))
        };

        var divider = new Border
        {
            Height = 1,
            Background = Ui.Brush(Palette.Hairline),
            VerticalAlignment = VerticalAlignment.Bottom
        };
        var headerHost = new Panel();
        headerHost.Children.Add(headerBorder);
        headerHost.Children.Add(divider);

        var root = new Grid { RowDefinitions = new RowDefinitions("Auto,*") };
        root.Children.Add(headerHost);
        Grid.SetRow(_host, 1);
        root.Children.Add(_host);

        Navigate(_section);
        return root;
    }

    private static string SectionTitle(MainSection section) => section switch
    {
        MainSection.Dashboard => "◔  Dashboard",
        MainSection.StudyLog => "📜  Study Log",
        MainSection.Subjects => "📚  Subjects",
        MainSection.Squad => "⚽  Squad",
        MainSection.Transfers => "↔  Transfers",
        _ => "🏆  Champions League"
    };

    public void Navigate(MainSection section)
    {
        _section = section;
        foreach (var (tabSection, button) in _tabs)
        {
            var selected = tabSection == section;
            button.SetColors(selected ? Color.FromArgb(36, Palette.Green.R, Palette.Green.G, Palette.Green.B) : Colors.Transparent,
                selected ? Palette.Green : Palette.Secondary);
        }

        if (!_pages.TryGetValue(section, out var page))
        {
            page = section switch
            {
                MainSection.Dashboard => new DashboardView(Store, this),
                MainSection.StudyLog => new StudyLogView(Store, this),
                MainSection.Subjects => new SubjectsView(Store, this),
                MainSection.Squad => new SquadView(Store, this),
                MainSection.Transfers => new TransfersView(Store, this),
                _ => new EuropeView(Store, this)
            };
            _pages[section] = page;
        }

        _page = page;
        _host.Content = page.View;
        RefreshChrome();
        page.Refresh();
    }

    private void RefreshChrome()
    {
        if (Store.HasCareer)
        {
            _seasonLabel.Text = $"SEASON {Store.State.SeasonNumber} · LEVEL {Store.Level}";
            _cashLabel.Text = $"{Store.State.ClubCash:N0} Club Cash";
        }
    }

    private void OnStoreChanged()
    {
        if (Store.HasCareer != _lastHasCareer)
        {
            _lastHasCareer = Store.HasCareer;
            Content = BuildRoot();
            return;
        }

        RefreshChrome();
        _page?.Refresh();
    }

    private async void ShowResetDialog()
    {
        var dialog = new ConfirmWindow(
            "Reset all progress?",
            "This permanently deletes your club, squad, trophies, Club Cash and study history, then returns you to club selection.",
            "Reset Everything");
        var confirmed = await dialog.ShowDialog<bool>(this);
        if (confirmed)
        {
            _pages.Clear();
            _page = null;
            _section = MainSection.Dashboard;
            Store.ResetCareer();
        }
    }

    public Task ShowDialogWindow(Window window) => window.ShowDialog(this);

    public void RebuildShell()
    {
        Content = BuildRoot();
    }
}
