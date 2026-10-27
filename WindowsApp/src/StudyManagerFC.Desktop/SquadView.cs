using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using StudyManagerFC.Core;

namespace StudyManagerFC.Desktop;

public class SquadView : IPage
{
    private readonly GameStore _store;
    private readonly MainWindow _window;

    private PitchView _pitch = null!;
    private TextBlock _overallValue = null!;
    private TextBlock _chemistryValue = null!;
    private TextBlock _attackValue = null!;
    private TextBlock _midfieldValue = null!;
    private TextBlock _defenceValue = null!;
    private TextBlock _valueValue = null!;
    private TextBlock _valueSubtitle = null!;
    private Border _xiPillHost = null!;
    private ChemistryRing _ringHost = null!;
    private Panel _ringPanel = null!;
    private TextBlock _ringLabel = null!;
    private StackPanel _lineupContent = null!;
    private StackPanel _playersContent = null!;
    private SegmentedControl _tabs = null!;
    private TextBox _search = null!;
    private ComboBox _groupFilter = null!;
    private TextBlock _playerCount = null!;
    private WrapPanel _playerGrid = null!;
    private string _signature = "";

    public Control View { get; }

    public SquadView(GameStore store, MainWindow window)
    {
        _store = store;
        _window = window;
        View = Build();
        Refresh();
    }

    private Control Build()
    {
        var page = new StackPanel { Spacing = 20 };
        page.Children.Add(BuildHeader());
        page.Children.Add(BuildMetrics());

        _tabs = new SegmentedControl(["Starting XI", "All Players"], width: 300);
        _tabs.SelectionChanged += index =>
        {
            _lineupContent.IsVisible = index == 0;
            _playersContent.IsVisible = index == 1;
        };
        page.Children.Add(_tabs);

        _lineupContent = BuildLineup();
        _playersContent = BuildPlayers();
        _playersContent.IsVisible = false;
        page.Children.Add(_lineupContent);
        page.Children.Add(_playersContent);

        var content = new Border
        {
            Padding = new Thickness(28),
            Child = page,
            MaxWidth = 1400,
            HorizontalAlignment = HorizontalAlignment.Center
        };
        return new ScrollViewer
        {
            Content = content,
            HorizontalScrollBarVisibility = Avalonia.Controls.Primitives.ScrollBarVisibility.Disabled
        };
    }

    private Control BuildHeader()
    {
        var header = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        header.Children.Add(Ui.ScreenHeader(
            $"{_store.ManagedClub?.Country ?? "Europe"} · {_store.ManagedClub?.Name ?? "My Club"}",
            "My Squad",
            "Build chemistry, cover every position, and give your club the best chance of European glory."));
        var club = _store.ManagedClub;
        if (club is not null)
        {
            var badge = new ClubBadgeControl(club, 66);
            Grid.SetColumn(badge, 1);
            badge.VerticalAlignment = VerticalAlignment.Top;
            header.Children.Add(badge);
        }
        return header;
    }

    private Control BuildMetrics()
    {
        var grid = new UniformGrid { Columns = 6 };
        grid.Children.Add(Metric("Overall", "▲", Palette.Green, out _overallValue));
        grid.Children.Add(Metric("Chemistry", "◉", Palette.Teal, out _chemistryValue));
        grid.Children.Add(Metric("Attack", "⚡", Palette.Orange, out _attackValue));
        grid.Children.Add(Metric("Midfield", "⤭", Palette.Blue, out _midfieldValue));
        grid.Children.Add(Metric("Defence", "⛨", Palette.Purple, out _defenceValue));
        grid.Children.Add(Metric("Squad Value", "💰", Palette.Gold, out _valueValue, out _valueSubtitle));
        return grid;
    }

    private static Border Metric(string title, string icon, Color tint, out TextBlock value)
        => Metric(title, icon, tint, out value, out _);

    private static Border Metric(string title, string icon, Color tint, out TextBlock value, out TextBlock subtitle)
    {
        var stack = new StackPanel { Spacing = 3 };
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
        row.Children.Add(Ui.Text(icon, 9, color: Ui.Brush(tint)));
        stack.Children.Add(row);
        value = Ui.Text("", 19, FontWeight.Bold);
        stack.Children.Add(value);
        stack.Children.Add(Ui.Text(title, 10, FontWeight.SemiBold));
        subtitle = Ui.Secondary("", 8);
        stack.Children.Add(subtitle);
        var card = Ui.Card(stack, 12, 13);
        card.Margin = new Thickness(0, 0, 8, 0);
        return card;
    }

    private StackPanel BuildLineup()
    {
        var layout = new Grid { ColumnDefinitions = new ColumnDefinitions("*,338") };
        var left = new StackPanel { Spacing = 10 };

        var row = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        var pills = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
        pills.Children.Add(Ui.Pill("4-3-3", Palette.Green, "⚽"));
        _xiPillHost = new Border { Child = Ui.Pill("XI", Palette.Green) };
        pills.Children.Add(_xiPillHost);
        row.Children.Add(pills);
        var hint = Ui.Secondary("Click any position to change it", 10);
        hint.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(hint, 1);
        row.Children.Add(hint);
        left.Children.Add(row);

        _pitch = new PitchView();
        _pitch.SlotSelected += ShowSlotPicker;
        left.Children.Add(_pitch);

        layout.Children.Add(left);

        var right = new StackPanel { Spacing = 16, Margin = new Thickness(18, 0, 0, 0) };
        var actions = new StackPanel { Spacing = 12 };
        actions.Children.Add(Ui.SectionHeader("Squad Actions", "Quick ways to shape your XI"));
        var autoPick = new ActionButton(
            "✨  Auto-pick Best XI",
            Palette.Green,
            Colors.White,
            radius: 10,
            padding: new Thickness(12, 7),
            fontSize: 11,
            align: HorizontalAlignment.Stretch);
        autoPick.Clicked += () => _store.AutoPickSquad();
        actions.Children.Add(autoPick);

        var chemistry = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12 };
        _ringPanel = new Panel { Width = 64, Height = 64 };
        _ringHost = new ChemistryRing(0);
        _ringPanel.Children.Add(_ringHost);
        chemistry.Children.Add(_ringPanel);

        var ringText = new StackPanel { Spacing = 2, VerticalAlignment = VerticalAlignment.Center };
        ringText.Children.Add(Ui.Text("Chemistry", 12, FontWeight.SemiBold));
        _ringLabel = Ui.Secondary("0/100", 10);
        ringText.Children.Add(_ringLabel);
        chemistry.Children.Add(ringText);
        actions.Children.Add(chemistry);
        right.Children.Add(Ui.Card(actions, 18));

        Grid.SetColumn(right, 1);
        layout.Children.Add(right);
        return new StackPanel { Children = { layout } };
    }

    private StackPanel BuildPlayers()
    {
        var wrapper = new StackPanel { Spacing = 14 };
        var filters = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,Auto,*,Auto") };
        _search = new TextBox { Watermark = "Search players or nations", Width = 300 };
        _search.TextChanged += (_, _) => RebuildPlayers(true);
        filters.Children.Add(_search);

        _groupFilter = new ComboBox
        {
            ItemsSource = new[] { "All positions" }
                .Concat(PositionGroupExtensionsDisplay.All.Select(group => group.DisplayName()))
                .ToList(),
            SelectedIndex = 0,
            Width = 160,
            Margin = new Thickness(10, 0, 0, 0)
        };
        _groupFilter.SelectionChanged += (_, _) => RebuildPlayers(true);
        Grid.SetColumn(_groupFilter, 1);
        filters.Children.Add(_groupFilter);

        _playerCount = Ui.Secondary("0 players", 10);
        _playerCount.HorizontalAlignment = HorizontalAlignment.Right;
        _playerCount.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(_playerCount, 3);
        filters.Children.Add(_playerCount);
        wrapper.Children.Add(filters);

        _playerGrid = new WrapPanel();
        wrapper.Children.Add(_playerGrid);
        return wrapper;
    }

    private void ShowSlotPicker(LineupSlot slot)
    {
        var dialog = new SlotPickerWindow(_store, slot);
        _ = dialog.ShowDialog(_window);
    }

    private void ShowPlayerDetail(Player player)
    {
        var dialog = new PlayerDetailWindow(_store, player);
        _ = dialog.ShowDialog(_window);
    }

    public void Refresh()
    {
        var club = _store.ManagedClub;
        var metrics = _store.SquadMetrics;
        _overallValue.Text = $"{metrics.Overall}";
        _chemistryValue.Text = $"{metrics.Chemistry}";
        _attackValue.Text = $"{metrics.Attack}";
        _midfieldValue.Text = $"{metrics.Midfield}";
        _defenceValue.Text = $"{metrics.Defence}";
        _valueValue.Text = metrics.TotalValue.ToString("N0");
        _valueSubtitle.Text = $"{metrics.PlayerCount} players";

        _xiPillHost.Child = _store.LineupIsComplete
            ? Ui.Pill("XI COMPLETE", Palette.Green, "✓")
            : Ui.Pill("INCOMPLETE XI", Palette.Orange, "!");

        _ringHost.SetChemistry(metrics.Chemistry);
        _ringLabel.Text = $"{metrics.Chemistry}/100";

        _pitch.Update(_store.LineupPlayersBySlot);

        var signature = BuildSignature();
        if (signature != _signature)
        {
            _signature = signature;
            RebuildPlayers(false);
        }

        _ = club;
    }

    private string BuildSignature()
    {
        var players = string.Join(",", _store.State.Players
            .OrderBy(player => player.Id)
            .Select(player => $"{player.Id}:{player.Overall}:{player.Potential}:{player.Age}:{player.Name}"));
        var lineup = string.Join(",", _store.State.Lineup.OrderBy(pair => pair.Key).Select(pair => $"{pair.Key}={pair.Value}"));
        var bench = string.Join(",", _store.State.Bench);
        return players + "|" + lineup + "|" + bench;
    }

    private void RebuildPlayers(bool force)
    {
        if (_playerGrid is null) return;
        _playerGrid.Children.Clear();
        var query = _search.Text?.Trim() ?? "";
        var groupIndex = Math.Max(0, _groupFilter?.SelectedIndex ?? 0);
        var filtered = _store.State.Players
            .Where(player =>
            {
                if (groupIndex > 0 && player.Position.Group() != PositionGroupExtensionsDisplay.All[groupIndex - 1]) return false;
                if (query.Length == 0) return true;
                return player.Name.Contains(query, StringComparison.OrdinalIgnoreCase)
                    || player.Position.DisplayName().Contains(query, StringComparison.OrdinalIgnoreCase)
                    || player.Nation.Name.Contains(query, StringComparison.OrdinalIgnoreCase);
            })
            .OrderByDescending(player => player.Overall)
            .ThenBy(player => player.Name, StringComparer.Ordinal)
            .ToList();

        _playerCount.Text = $"{filtered.Count} players";

        foreach (var player in filtered)
        {
            var stack = new StackPanel { Spacing = 7 };
            stack.Children.Add(new PlayerCardView(player, 176));
            stack.Children.Add(StatusPill(player));

            var holder = new Border
            {
                Child = stack,
                Margin = new Thickness(0, 0, 14, 16),
                Background = Brushes.Transparent,
                Cursor = new Cursor(StandardCursorType.Hand)
            };
            var captured = player;
            holder.PointerPressed += (_, args) =>
            {
                if (args.GetCurrentPoint(holder).Properties.IsLeftButtonPressed) ShowPlayerDetail(captured);
            };
            _playerGrid.Children.Add(holder);
        }

        if (filtered.Count == 0)
        {
            var empty = new StackPanel
            {
                Spacing = 6,
                Margin = new Thickness(0, 30),
                HorizontalAlignment = HorizontalAlignment.Center
            };
            empty.Children.Add(Ui.Text("👤", 26, color: Ui.Brush(Palette.Green)));
            empty.Children.Add(Ui.Text("No players found", 14, FontWeight.SemiBold));
            var message = Ui.Secondary("Change your filters to see the rest of your squad.", 11, TextWrapping.Wrap);
            message.TextAlignment = TextAlignment.Center;
            empty.Children.Add(message);
            _playerGrid.Children.Add(empty);
        }
    }

    private Control StatusPill(Player player)
    {
        var slotId = _store.State.Lineup.FirstOrDefault(pair => pair.Value == player.Id).Key;
        if (slotId is not null && LineupSlot.Slot(slotId) is { } slot)
        {
            return Ui.Pill($"STARTING {slot.Label}", Palette.Green, "✓");
        }
        if (_store.State.Bench.Contains(player.Id)) return Ui.Pill("ON BENCH", Palette.Gold, "▣");
        return Ui.Pill("RESERVE", Palette.Secondary, "•");
    }
}

public static class PositionGroupExtensionsDisplay
{
    public static readonly PositionGroup[] All =
        [PositionGroup.Goalkeeper, PositionGroup.Defence, PositionGroup.Midfield, PositionGroup.Attack];
}
