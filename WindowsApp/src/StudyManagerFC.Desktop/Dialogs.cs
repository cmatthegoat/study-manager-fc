using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using StudyManagerFC.Core;

namespace StudyManagerFC.Desktop;

public class ConfirmWindow : Window
{
    public ConfirmWindow(string title, string message, string confirmLabel)
    {
        Title = title;
        Width = 480;
        Height = 240;
        CanResize = false;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Background = AppBackground.Brush;

        var stack = new StackPanel { Spacing = 14, Margin = new Thickness(24) };
        stack.Children.Add(Ui.Text(title, 20, FontWeight.Bold));
        stack.Children.Add(Ui.Secondary(message, 12, TextWrapping.Wrap));

        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 10,
            HorizontalAlignment = HorizontalAlignment.Right
        };
        var cancel = new ActionButton("Cancel", Color.FromArgb(20, 20, 32, 27), Palette.Ink, radius: 9, padding: new Thickness(16, 8));
        cancel.Clicked += () => Close(false);
        var confirm = new ActionButton(confirmLabel, Palette.Red, Colors.White, radius: 9, padding: new Thickness(16, 8));
        confirm.Clicked += () => Close(true);
        buttons.Children.Add(cancel);
        buttons.Children.Add(confirm);
        stack.Children.Add(buttons);

        Content = stack;
    }
}

public class PlayerDetailWindow : Window
{
    private readonly GameStore _store;
    private readonly Player _player;

    public PlayerDetailWindow(GameStore store, Player player)
    {
        _store = store;
        _player = player;
        Title = "Player Profile";
        Width = 740;
        Height = 560;
        CanResize = false;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Background = AppBackground.Brush;
        Content = Build();
    }

    private Control Build()
    {
        var root = new StackPanel { Spacing = 18, Margin = new Thickness(26) };

        var header = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        var titles = new StackPanel { Spacing = 2 };
        titles.Children.Add(Ui.Eyebrow(_player.Rarity.DisplayName(), Ui.RarityColor(_player.Rarity)));
        titles.Children.Add(Ui.Text("Player Profile", 20, FontWeight.Bold));
        header.Children.Add(titles);
        var close = new ActionButton("Close", Color.FromArgb(18, 20, 32, 27), Palette.Ink, radius: 9, padding: new Thickness(14, 6));
        close.Clicked += Close;
        Grid.SetColumn(close, 1);
        header.Children.Add(close);
        root.Children.Add(header);

        var body = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*") };
        body.Children.Add(new PlayerCardView(_player, 230));

        var details = new StackPanel { Spacing = 14, Margin = new Thickness(24, 0, 0, 0) };
        var nameBlock = new StackPanel { Spacing = 3 };
        nameBlock.Children.Add(Ui.Text(_player.Name, 24, FontWeight.Bold));
        nameBlock.Children.Add(Ui.Secondary($"{_player.Nation.Flag} {_player.Nation.Name} · {_player.Position.DisplayName()}", 11));
        details.Children.Add(nameBlock);

        var pills = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        pills.Children.Add(Ui.Pill($"OVR {_player.Overall}", Ui.RarityColor(_player.Rarity)));
        pills.Children.Add(Ui.Pill($"POT {_player.Potential}", Palette.Teal));
        pills.Children.Add(Ui.Pill($"AGE {_player.Age}", Palette.Secondary));
        details.Children.Add(pills);

        var attributes = new StackPanel { Spacing = 7 };
        attributes.Children.Add(AttributeBar("Pace", _player.Attributes.Pace));
        attributes.Children.Add(AttributeBar("Shooting", _player.Attributes.Shooting));
        attributes.Children.Add(AttributeBar("Passing", _player.Attributes.Passing));
        attributes.Children.Add(AttributeBar("Defending", _player.Attributes.Defending));
        attributes.Children.Add(AttributeBar("Physical", _player.Attributes.Physical));
        details.Children.Add(attributes);

        details.Children.Add(Ui.Hairline());

        var values = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        var market = new StackPanel { Spacing = 2 };
        market.Children.Add(Ui.Secondary("Market value", 9));
        market.Children.Add(Ui.Text(_player.MarketValue.ToString("N0"), 15, FontWeight.Bold));
        values.Children.Add(market);
        var release = new StackPanel { Spacing = 2 };
        release.Children.Add(Ui.Secondary("Release value", 9));
        var releaseValue = Ui.Text(_player.ReleaseValue.ToString("N0"), 15, FontWeight.Bold, Ui.Brush(Palette.Gold));
        releaseValue.HorizontalAlignment = HorizontalAlignment.Right;
        release.Children.Add(releaseValue);
        Grid.SetColumn(release, 1);
        values.Children.Add(release);
        details.Children.Add(values);

        details.Children.Add(BuildActions());

        Grid.SetColumn(details, 1);
        body.Children.Add(details);
        root.Children.Add(body);
        return root;
    }

    private Control BuildActions()
    {
        var actions = new StackPanel { Spacing = 8 };
        var slotId = _store.State.Lineup.FirstOrDefault(pair => pair.Value == _player.Id).Key;

        if (slotId is not null)
        {
            var remove = new ActionButton("↓  Remove from Starting XI", Color.FromArgb(18, 20, 32, 27), Palette.Ink,
                radius: 9, padding: new Thickness(12, 7), fontSize: 11, align: HorizontalAlignment.Stretch);
            remove.Clicked += () =>
            {
                _store.RemoveFromLineup(slotId);
                Close();
            };
            actions.Children.Add(remove);
        }
        else if (_store.State.Bench.Contains(_player.Id))
        {
            var remove = new ActionButton("↓  Remove from Bench", Color.FromArgb(18, 20, 32, 27), Palette.Ink,
                radius: 9, padding: new Thickness(12, 7), fontSize: 11, align: HorizontalAlignment.Stretch);
            remove.Clicked += () =>
            {
                _store.RemoveFromBench(_player.Id);
                Close();
            };
            actions.Children.Add(remove);
        }
        else
        {
            var add = new ActionButton("+  Add to Squad", Palette.Green, Colors.White,
                radius: 9, padding: new Thickness(12, 7), fontSize: 11, align: HorizontalAlignment.Stretch);
            add.Clicked += () =>
            {
                _store.AddToSquad(_player.Id);
                Close();
            };
            actions.Children.Add(add);

            if (_store.State.Bench.Count < GameRules.BenchLimit)
            {
                var bench = new ActionButton("▣  Add to Bench", Color.FromArgb(18, 20, 32, 27), Palette.Ink,
                    radius: 9, padding: new Thickness(12, 7), fontSize: 11, align: HorizontalAlignment.Stretch);
                bench.Clicked += () =>
                {
                    _store.AddToBench(_player.Id);
                    Close();
                };
                actions.Children.Add(bench);
            }
        }

        var release = new ActionButton($"Release for {_player.ReleaseValue:N0}", Colors.Transparent, Palette.Red,
            radius: 9, padding: new Thickness(8, 4), fontSize: 10, align: HorizontalAlignment.Stretch);
        release.Clicked += async () =>
        {
            var confirm = new ConfirmWindow(
                $"Release {_player.Name}?",
                $"You will receive {_player.ReleaseValue:N0} Club Cash. This cannot be undone.",
                "Release Player");
            var confirmed = await confirm.ShowDialog<bool>(this);
            if (!confirmed) return;
            _store.ReleasePlayer(_player.Id);
            Close();
        };
        actions.Children.Add(release);

        return actions;
    }

    private static Control AttributeBar(string label, int value)
    {
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("60,*,26") };
        var name = Ui.Secondary(label, 9);
        grid.Children.Add(name);
        var progress = new ProgressBar
        {
            Minimum = 0,
            Maximum = 100,
            Value = value,
            Height = 5,
            Foreground = Ui.Brush(Palette.Green),
            Background = Ui.Brush(Color.FromArgb(20, 20, 32, 27)),
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(0, 0, 8, 0)
        };
        Grid.SetColumn(progress, 1);
        grid.Children.Add(progress);
        var number = Ui.Text($"{value}", 9, FontWeight.Bold);
        number.HorizontalAlignment = HorizontalAlignment.Right;
        Grid.SetColumn(number, 2);
        grid.Children.Add(number);
        return grid;
    }
}

public class SlotPickerWindow : Window
{
    private readonly GameStore _store;
    private readonly LineupSlot _slot;

    public SlotPickerWindow(GameStore store, LineupSlot slot)
    {
        _store = store;
        _slot = slot;
        Title = $"Select player · {slot.Label}";
        Width = 600;
        Height = 680;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Background = AppBackground.Brush;
        Content = Build();
    }

    private Control Build()
    {
        var root = new DockPanel { Margin = new Thickness(22) };

        var header = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto"), Margin = new Thickness(0, 0, 0, 14) };
        var titles = new StackPanel { Spacing = 2 };
        titles.Children.Add(Ui.Eyebrow("Select Player"));
        titles.Children.Add(Ui.Text($"{_slot.Position.DisplayName()} · {_slot.Label}", 20, FontWeight.Bold));
        header.Children.Add(titles);
        var cancel = new ActionButton("Cancel", Color.FromArgb(18, 20, 32, 27), Palette.Ink, radius: 9, padding: new Thickness(14, 6));
        cancel.Clicked += Close;
        Grid.SetColumn(cancel, 1);
        header.Children.Add(cancel);
        DockPanel.SetDock(header, Dock.Top);
        root.Children.Add(header);

        _store.State.Lineup.TryGetValue(_slot.Id, out var currentId);
        var current = _store.PlayerFor(currentId);
        if (current is not null && currentId != Guid.Empty)
        {
            var currentRow = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
            currentRow.Children.Add(PlayerRow(current, true));
            var remove = new ActionButton("Remove from XI", Colors.Transparent, Palette.Red, radius: 8, padding: new Thickness(10, 6), fontSize: 10);
            remove.Clicked += () =>
            {
                _store.RemoveFromLineup(_slot.Id);
                Close();
            };
            Grid.SetColumn(remove, 1);
            remove.VerticalAlignment = VerticalAlignment.Center;
            currentRow.Children.Add(remove);
            var currentCard = new Border
            {
                Child = currentRow,
                Padding = new Thickness(10),
                Margin = new Thickness(0, 0, 0, 10),
                CornerRadius = new CornerRadius(12),
                Background = Ui.Brush(Color.FromArgb(30, Palette.Red.R, Palette.Red.G, Palette.Red.B))
            };
            DockPanel.SetDock(currentCard, Dock.Top);
            root.Children.Add(currentCard);
        }

        var list = new StackPanel { Spacing = 4 };
        var candidates = _store.State.Players
            .OrderByDescending(player => player.AdjustedRating(_slot))
            .ThenByDescending(player => player.Overall)
            .ToList();
        foreach (var player in candidates)
        {
            var row = PlayerRow(player, player.Id == currentId);
            row.Cursor = new Cursor(StandardCursorType.Hand);
            var card = new Border
            {
                Child = row,
                Padding = new Thickness(10, 7),
                CornerRadius = new CornerRadius(10),
                Background = Ui.Brush(player.Position.Group() == _slot.Position.Group()
                    ? Color.FromArgb(18, Palette.Green.R, Palette.Green.G, Palette.Green.B)
                    : Colors.Transparent)
            };
            card.PointerEntered += (_, _) => card.Background = Ui.Brush(Color.FromArgb(26, 20, 32, 27));
            card.PointerExited += (_, _) => card.Background = Ui.Brush(player.Position.Group() == _slot.Position.Group()
                ? Color.FromArgb(18, Palette.Green.R, Palette.Green.G, Palette.Green.B)
                : Colors.Transparent);
            var captured = player;
            card.PointerPressed += (_, args) =>
            {
                if (!args.GetCurrentPoint(card).Properties.IsLeftButtonPressed) return;
                _store.Assign(captured.Id, _slot.Id);
                Close();
            };
            list.Children.Add(card);
        }

        root.Children.Add(new ScrollViewer { Content = list });
        return root;
    }

    private Control PlayerRow(Player player, bool isCurrent)
    {
        var row = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*,Auto") };
        var accent = Ui.RarityColor(player.Rarity);
        row.Children.Add(new Border
        {
            Width = 38,
            Height = 38,
            CornerRadius = new CornerRadius(19),
            Background = Ui.Brush(Color.FromArgb(46, accent.R, accent.G, accent.B)),
            Child = Ui.Text($"{player.Overall}", 13, FontWeight.Black)
        });

        var text = new StackPanel { Spacing = 1, Margin = new Thickness(10, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
        text.Children.Add(Ui.Text(player.Name, 12, FontWeight.SemiBold));
        text.Children.Add(Ui.Secondary(
            $"{player.Position.Abbreviation()} · {player.Nation.Flag} {player.NationCode} · Age {player.Age} · POT {player.Potential}", 9));
        Grid.SetColumn(text, 1);
        row.Children.Add(text);

        var pills = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 5, VerticalAlignment = VerticalAlignment.Center };
        if (player.Position == _slot.Position) pills.Children.Add(Ui.Pill("NATURAL", Palette.Green));
        else if (player.Position.Group() == _slot.Position.Group()) pills.Children.Add(Ui.Pill("FITS", Palette.Teal));
        else pills.Children.Add(Ui.Pill("OUT OF POSITION", Palette.Orange));
        if (!isCurrent && _store.State.Bench.Contains(player.Id)) pills.Children.Add(Ui.Pill("BENCH", Palette.Secondary));
        if (isCurrent) pills.Children.Add(Ui.Text("✓", 14, FontWeight.Bold, Ui.Brush(Palette.Green)));
        Grid.SetColumn(pills, 2);
        row.Children.Add(pills);
        return row;
    }
}

public class MatchReportWindow : Window
{
    private readonly MatchReport _report;
    private readonly string? _userClubId;

    public MatchReportWindow(MatchReport report, string? userClubId)
    {
        _report = report;
        _userClubId = userClubId;
        Title = "Match Report";
        Width = 720;
        Height = 740;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Background = AppBackground.Brush;
        Content = Build();
    }

    private Control Build()
    {
        var home = ClubDatabase.Club(_report.HomeClubID);
        var away = ClubDatabase.Club(_report.AwayClubID);
        var root = new DockPanel { Margin = new Thickness(24) };

        var header = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto"), Margin = new Thickness(0, 0, 0, 16) };
        var titles = new StackPanel { Spacing = 2 };
        titles.Children.Add(Ui.Eyebrow(_report.Phase.DisplayName()));
        titles.Children.Add(Ui.Text("Match Report", 20, FontWeight.Bold));
        header.Children.Add(titles);
        var done = new ActionButton("Done", Palette.Green, Colors.White, radius: 9, padding: new Thickness(16, 7));
        done.Clicked += Close;
        Grid.SetColumn(done, 1);
        header.Children.Add(done);
        DockPanel.SetDock(header, Dock.Top);
        root.Children.Add(header);

        var body = new StackPanel { Spacing = 18 };

        var scoreRow = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto,*") };
        scoreRow.Children.Add(TeamBlock(home));
        var score = new StackPanel { Spacing = 4, VerticalAlignment = VerticalAlignment.Center };
        var scoreText = Ui.Text(_report.Scoreline.Split(" (")[0], 36, FontWeight.Black);
        scoreText.TextAlignment = TextAlignment.Center;
        score.Children.Add(scoreText);
        var caption = _report.HomePenalties.HasValue
            ? Ui.Text($"{_report.HomePenalties}-{_report.AwayPenalties} on penalties", 11, FontWeight.SemiBold, Ui.Brush(Palette.Gold))
            : Ui.Secondary("FULL TIME", 9, TextWrapping.NoWrap);
        caption.TextAlignment = TextAlignment.Center;
        score.Children.Add(caption);
        score.Width = 150;
        Grid.SetColumn(score, 1);
        scoreRow.Children.Add(score);
        var awayBlock = TeamBlock(away);
        Grid.SetColumn(awayBlock, 2);
        scoreRow.Children.Add(awayBlock);
        body.Children.Add(Ui.Card(scoreRow, 18));

        var summary = Ui.Secondary(_report.Summary, 12, TextWrapping.Wrap);
        summary.TextAlignment = TextAlignment.Center;
        summary.HorizontalAlignment = HorizontalAlignment.Center;
        summary.MaxWidth = 560;
        body.Children.Add(summary);

        var scorers = new Grid { ColumnDefinitions = new ColumnDefinitions("*,*") };
        scorers.Children.Add(ScorerColumn(home, _report.ScorersForHome));
        var awayScorers = ScorerColumn(away, _report.ScorersForAway);
        awayScorers.Margin = new Thickness(12, 0, 0, 0);
        Grid.SetColumn(awayScorers, 1);
        scorers.Children.Add(awayScorers);
        body.Children.Add(scorers);

        var moments = new StackPanel { Spacing = 10 };
        moments.Children.Add(Ui.SectionHeader("Key Moments", "Every goal in chronological order"));
        if (_report.Events.Count == 0)
        {
            moments.Children.Add(Ui.Secondary("No goals were scored.", 12));
        }
        else
        {
            foreach (var matchEvent in _report.Events)
            {
                var row = new Grid { ColumnDefinitions = new ColumnDefinitions("40,Auto,*,Auto") };
                var minute = Ui.Text($"{matchEvent.Minute}'", 11, FontWeight.Bold, Ui.Brush(Palette.Green));
                minute.TextAlignment = TextAlignment.Right;
                row.Children.Add(minute);
                var dot = new Border
                {
                    Width = 7,
                    Height = 7,
                    CornerRadius = new CornerRadius(4),
                    Margin = new Thickness(10, 0, 10, 0),
                    Background = Ui.Brush(Color.Parse("#" + (ClubDatabase.Club(matchEvent.ClubID)?.PrimaryHex.TrimStart('#') ?? "888888"))),
                    VerticalAlignment = VerticalAlignment.Center
                };
                Grid.SetColumn(dot, 1);
                row.Children.Add(dot);
                var name = Ui.Text(matchEvent.Scorer, 12, FontWeight.SemiBold);
                Grid.SetColumn(name, 2);
                row.Children.Add(name);
                var detail = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6, VerticalAlignment = VerticalAlignment.Center };
                if (matchEvent.IsPenalty) detail.Children.Add(Ui.Pill("PEN", Palette.Gold));
                detail.Children.Add(Ui.Secondary(ClubDatabase.Club(matchEvent.ClubID)?.ShortName ?? "", 10));
                Grid.SetColumn(detail, 3);
                row.Children.Add(detail);
                moments.Children.Add(row);
            }
        }
        body.Children.Add(Ui.Card(moments, 18));

        var ratings = new Grid { ColumnDefinitions = new ColumnDefinitions("*,*") };
        ratings.Children.Add(RatingBlock("Home rating", _report.HomeRating, home));
        var awayRating = RatingBlock("Away rating", _report.AwayRating, away);
        awayRating.Margin = new Thickness(12, 0, 0, 0);
        Grid.SetColumn(awayRating, 1);
        ratings.Children.Add(awayRating);
        body.Children.Add(ratings);

        root.Children.Add(new ScrollViewer { Content = body });
        return root;
    }

    private Control TeamBlock(Club? club)
    {
        var stack = new StackPanel { Spacing = 6, HorizontalAlignment = HorizontalAlignment.Center };
        if (club is not null) stack.Children.Add(new ClubBadgeControl(club, 52) { HorizontalAlignment = HorizontalAlignment.Center });
        stack.Children.Add(Ui.Text(club?.ShortName ?? "—", 13, FontWeight.SemiBold));
        if (club?.Id == _userClubId)
        {
            stack.Children.Add(Ui.Text("YOUR CLUB", 8, FontWeight.Bold, Ui.Brush(Palette.Green)));
        }
        return stack;
    }

    private static Control ScorerColumn(Club? club, IReadOnlyList<ScorerTally> scorers)
    {
        var stack = new StackPanel { Spacing = 6 };
        var header = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
        if (club is not null) header.Children.Add(new ClubBadgeControl(club, 20));
        header.Children.Add(Ui.Text(club?.Name ?? "—", 11, FontWeight.SemiBold));
        stack.Children.Add(header);
        if (scorers.Count == 0)
        {
            stack.Children.Add(Ui.Text("No scorers", 11, color: Ui.Brush(Palette.Tertiary)));
        }
        else
        {
            foreach (var scorer in scorers)
            {
                var row = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
                row.Children.Add(Ui.Text(scorer.Name, 11));
                var goals = Ui.Text($"x{scorer.Goals}", 10, FontWeight.Bold, Ui.Brush(Palette.Secondary));
                goals.HorizontalAlignment = HorizontalAlignment.Right;
                Grid.SetColumn(goals, 1);
                row.Children.Add(goals);
                stack.Children.Add(row);
            }
        }
        return Ui.Card(stack, 14, 15);
    }

    private static Control RatingBlock(string label, int value, Club? club)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        if (club is not null) row.Children.Add(new ClubBadgeControl(club, 26));
        var text = new StackPanel { Spacing = 1 };
        text.Children.Add(Ui.Secondary(label, 9));
        text.Children.Add(Ui.Text($"{value}", 17, FontWeight.Bold));
        row.Children.Add(text);
        return Ui.Card(row, 12, 14);
    }
}
