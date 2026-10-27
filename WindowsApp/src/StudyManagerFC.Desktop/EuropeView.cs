using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using StudyManagerFC.Core;

namespace StudyManagerFC.Desktop;

public class EuropeView : IPage
{
    private readonly GameStore _store;
    private readonly MainWindow _window;
    private readonly ContentControl _content = new();
    private string _signature = "";
    private string? _error;

    public Control View { get; }

    public EuropeView(GameStore store, MainWindow window)
    {
        _store = store;
        _window = window;
        View = new ScrollViewer
        {
            Content = _content,
            HorizontalScrollBarVisibility = Avalonia.Controls.Primitives.ScrollBarVisibility.Disabled
        };
        Refresh();
    }

    public void Refresh()
    {
        var signature = BuildSignature();
        if (signature == _signature) return;
        _signature = signature;
        _content.Content = Build();
    }

    private string BuildSignature()
    {
        var season = _store.State.Season;
        return string.Join("|",
            season?.Phase,
            season?.NextLeagueRound,
            season?.Reports.Count,
            season?.ChampionClubID,
            season?.LeagueRoundsPlayed,
            _store.State.AvailableMatchMinutes,
            _store.State.ClubCash,
            _store.State.Trophies.Count,
            _store.LineupIsComplete,
            _store.State.SeasonNumber,
            string.Join(",", _store.State.Lineup.Select(pair => $"{pair.Key}={pair.Value}")),
            _error);
    }

    private Control Build()
    {
        var stack = new StackPanel { Spacing = 22 };
        stack.Children.Add(BuildHeader());

        var columns = new Grid { ColumnDefinitions = new ColumnDefinitions("*,330") };
        columns.Children.Add(MatchdayCard());
        var seasonCard = SeasonStatusCard();
        seasonCard.Margin = new Thickness(18, 0, 0, 0);
        Grid.SetColumn(seasonCard, 1);
        columns.Children.Add(seasonCard);
        stack.Children.Add(columns);

        stack.Children.Add(StandingsCard());
        if (_store.LatestReports.Count > 0) stack.Children.Add(ResultsCard());
        if (_store.Trophies.Count > 0) stack.Children.Add(TrophyCard());

        return new Border
        {
            Padding = new Thickness(28),
            Child = stack,
            MaxWidth = 1400,
            HorizontalAlignment = HorizontalAlignment.Center
        };
    }

    private Control BuildHeader()
    {
        var header = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        header.Children.Add(Ui.ScreenHeader(
            $"Season {_store.State.SeasonNumber} · {_store.Season?.Phase.DisplayName() ?? "No Season"}",
            "Champions League",
            "Log study minutes to unlock each matchday, then simulate the round and chase the trophy."));
        if (_store.ManagedClub is { } club)
        {
            var badge = new ClubBadgeControl(club, 66);
            Grid.SetColumn(badge, 1);
            badge.VerticalAlignment = VerticalAlignment.Top;
            header.Children.Add(badge);
        }
        return header;
    }

    private Control MatchdayCard()
    {
        var stack = new StackPanel { Spacing = 14 };
        var title = _store.IsSeasonComplete ? "Season Complete" : "Next Match";
        stack.Children.Add(Ui.SectionHeader(title, MatchdaySubtitle()));

        if (_store.IsSeasonComplete)
        {
            stack.Children.Add(SeasonCompleteContent());
        }
        else if (_store.UserCurrentFixture is { } fixture && _store.ManagedClub is { } club)
        {
            stack.Children.Add(FixtureContent(fixture, club));
            stack.Children.Add(SimulateControls());
        }
        else
        {
            stack.Children.Add(SpectatorContent());
            stack.Children.Add(SimulateControls());
        }

        if (_error is not null)
        {
            var error = Ui.Text(_error, 11, color: Ui.Brush(Palette.Red), wrapping: TextWrapping.Wrap);
            error.Margin = new Thickness(0, 4, 0, 0);
            stack.Children.Add(error);
        }

        return Ui.Card(stack, 20);
    }

    private string MatchdaySubtitle()
    {
        if (_store.Season is null) return "No active season";
        var season = _store.Season;
        return season.Phase switch
        {
            SeasonPhase.League => $"Matchday {Math.Min(season.NextLeagueRound, 8)} of 8 · {_store.CurrentFixtures.Count} matches",
            SeasonPhase.Complete => $"Season {season.Number} is in the books",
            _ => $"{season.Phase.DisplayName()} · {_store.CurrentFixtures.Count} matches"
        };
    }

    private Control FixtureContent(Fixture fixture, Club club)
    {
        var home = ClubDatabase.Club(fixture.HomeClubID);
        var away = ClubDatabase.Club(fixture.AwayClubID);
        var isHome = fixture.HomeClubID == club.Id;

        var stack = new StackPanel { Spacing = 14 };

        var teams = new Grid { ColumnDefinitions = new ColumnDefinitions("*,96,*") };
        teams.Children.Add(TeamBlock(home, home?.Id == club.Id));
        var middle = new StackPanel { Spacing = 3, VerticalAlignment = VerticalAlignment.Center };
        if (fixture.IsSimulated)
        {
            var score = Ui.Text(fixture.Scoreline, 20, FontWeight.Black);
            score.TextAlignment = TextAlignment.Center;
            middle.Children.Add(score);
        }
        else
        {
            var vs = Ui.Text("VS", 15, FontWeight.Black, Ui.Brush(Palette.Secondary));
            vs.TextAlignment = TextAlignment.Center;
            middle.Children.Add(vs);
        }
        var venue = Ui.Text(isHome ? "HOME" : "AWAY", 8, FontWeight.Bold, Ui.Brush(Palette.Green));
        venue.TextAlignment = TextAlignment.Center;
        middle.Children.Add(venue);
        Grid.SetColumn(middle, 1);
        teams.Children.Add(middle);
        var awayBlock = TeamBlock(away, away?.Id == club.Id);
        Grid.SetColumn(awayBlock, 2);
        teams.Children.Add(awayBlock);
        teams.Margin = new Thickness(0, 6);
        stack.Children.Add(teams);

        var pills = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
        var phase = _store.Season?.Phase ?? SeasonPhase.League;
        pills.Children.Add(Ui.Pill(phase.ShortName().ToUpperInvariant(), Palette.Gold, "⚑"));
        pills.Children.Add(_store.LineupIsComplete
            ? Ui.Pill("XI READY", Palette.Green, "✓")
            : Ui.Pill("XI INCOMPLETE", Palette.Orange, "!"));
        var metrics = _store.SquadMetrics;
        pills.Children.Add(Ui.Pill($"{metrics.Overall} OVR · {metrics.Chemistry} CHEM", Palette.Teal));
        stack.Children.Add(pills);

        var readiness = new StackPanel { Spacing = 5 };
        var readinessHeader = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        readinessHeader.Children.Add(Ui.Text("Match readiness", 10, FontWeight.SemiBold));
        var value = Ui.Text($"{Math.Min(_store.State.AvailableMatchMinutes, GameRules.MinutesPerMatch)} / {GameRules.MinutesPerMatch} min",
            10, FontWeight.Bold, Ui.Brush(_store.MatchReadiness >= 1 ? Palette.Green : Palette.Secondary));
        value.HorizontalAlignment = HorizontalAlignment.Right;
        Grid.SetColumn(value, 1);
        readinessHeader.Children.Add(value);
        readiness.Children.Add(readinessHeader);
        readiness.Children.Add(new ReadinessBar(8));
        stack.Children.Add(readiness);

        var blocker = BlockingReason();
        if (blocker is not null)
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 7 };
            row.Children.Add(Ui.Text("🔒", 10, color: Ui.Brush(Palette.Orange)));
            row.Children.Add(Ui.Secondary(blocker, 11, TextWrapping.Wrap));
            stack.Children.Add(new Border
            {
                Child = row,
                Padding = new Thickness(10),
                CornerRadius = new CornerRadius(10),
                Background = Ui.Brush(Color.FromArgb(22, Palette.Orange.R, Palette.Orange.G, Palette.Orange.B))
            });
        }

        return stack;
    }

    private Control SpectatorContent()
    {
        var stack = new StackPanel { Spacing = 10 };
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        row.Children.Add(Ui.Text("🔭", 16, color: Ui.Brush(Palette.Teal)));
        var text = new StackPanel { Spacing = 1 };
        text.Children.Add(Ui.Text("No fixture for your club", 14, FontWeight.SemiBold));
        text.Children.Add(Ui.Secondary("Simulating plays the rest of the round. Later rounds will include you if you qualify.", 10, TextWrapping.Wrap));
        row.Children.Add(text);
        stack.Children.Add(new Border
        {
            Child = row,
            Padding = new Thickness(12),
            CornerRadius = new CornerRadius(12),
            Background = Ui.Brush(Color.FromArgb(20, Palette.Teal.R, Palette.Teal.G, Palette.Teal.B))
        });

        var fixture = _store.NextFixtureForUser;
        var club = _store.ManagedClub;
        if (fixture is not null && club is not null)
        {
            var opponentId = fixture.HomeClubID == club.Id ? fixture.AwayClubID : fixture.HomeClubID;
            var opponent = ClubDatabase.Club(opponentId);
            var nextRow = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*,Auto") };
            if (opponent is not null) nextRow.Children.Add(new ClubBadgeControl(opponent, 30));
            var nextText = new StackPanel { Spacing = 1, Margin = new Thickness(10, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
            nextText.Children.Add(Ui.Text("NEXT UP", 8, FontWeight.Black, Ui.Brush(Palette.Secondary)));
            nextText.Children.Add(Ui.Text(
                $"{(fixture.HomeClubID == club.Id ? "vs" : "away at")} {opponent?.ShortName ?? "TBD"}", 12, FontWeight.SemiBold));
            Grid.SetColumn(nextText, 1);
            nextRow.Children.Add(nextText);
            var label = Ui.Secondary(fixture.Phase == SeasonPhase.League ? $"Matchday {fixture.Round}" : fixture.Phase.DisplayName(), 10);
            Grid.SetColumn(label, 2);
            label.VerticalAlignment = VerticalAlignment.Center;
            nextRow.Children.Add(label);
            stack.Children.Add(new Border
            {
                Child = nextRow,
                Padding = new Thickness(10),
                CornerRadius = new CornerRadius(10),
                Background = Ui.Brush(Color.FromArgb(10, 20, 32, 27))
            });
        }
        return stack;
    }

    private Control SimulateControls()
    {
        var stack = new StackPanel { Spacing = 8 };
        var button = new ActionButton(_store.StageButtonLabel, Palette.Green, Colors.White,
            radius: 10, padding: new Thickness(14, 9), fontSize: 12, align: HorizontalAlignment.Stretch);
        button.SetEnabledState(_store.CanSimulateCurrentStage);
        button.Clicked += Simulate;
        stack.Children.Add(button);
        stack.Children.Add(Ui.Secondary(
            _store.UserCurrentFixture is null
                ? "Spectating: simulating does not use your study minutes."
                : $"Simulating your match uses {GameRules.MinutesPerMatch} study minutes.",
            9,
            TextWrapping.Wrap));
        return stack;
    }

    private Control SeasonCompleteContent()
    {
        var stack = new StackPanel { Spacing = 12 };
        var champion = _store.ChampionClub;
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12 };
        if (champion is not null)
        {
            row.Children.Add(new ClubBadgeControl(champion, 52));
            var text = new StackPanel { Spacing = 1 };
            text.Children.Add(Ui.Text($"{_store.Season?.Number ?? 0} CHAMPIONS", 8, FontWeight.Black, Ui.Brush(Palette.Gold)));
            text.Children.Add(Ui.Text(champion.Name, 18, FontWeight.Bold));
            text.Children.Add(Ui.Secondary($"You finished: {_store.FinalUserFinish}", 11));
            row.Children.Add(text);
        }
        else
        {
            row.Children.Add(Ui.Text("🏆", 26, color: Ui.Brush(Palette.Gold)));
            row.Children.Add(Ui.Text("The trophy has been lifted.", 15, FontWeight.SemiBold));
        }
        stack.Children.Add(row);

        var next = new ActionButton($"Start Season {_store.State.SeasonNumber + 1}  →", Palette.Green, Colors.White,
            radius: 10, padding: new Thickness(14, 9), fontSize: 12, align: HorizontalAlignment.Stretch);
        next.Clicked += StartNextSeason;
        stack.Children.Add(next);
        stack.Children.Add(Ui.Secondary(
            "Players age and improve, retirements open up space, and a new crop of youth prospects joins the free-agent pool.",
            9,
            TextWrapping.Wrap));
        return stack;
    }

    private Control SeasonStatusCard()
    {
        var stack = new StackPanel { Spacing = 10 };
        stack.Children.Add(Ui.SectionHeader("Season Status", "Your European campaign"));
        stack.Children.Add(StatusRow("Phase", _store.Season?.Phase.DisplayName() ?? "—", Palette.Green));
        stack.Children.Add(StatusRow("League position", SeasonEngine.Ordinal(_store.UserLeaguePosition), Palette.Teal));
        stack.Children.Add(StatusRow("Study bank", $"{_store.State.AvailableMatchMinutes} min", Palette.Gold));
        stack.Children.Add(StatusRow("Titles won", $"{_store.UserTitles}", Palette.Gold));
        stack.Children.Add(StatusRow("Seasons completed", $"{_store.CompletedSeasons}", Palette.Green));
        stack.Children.Add(Ui.Hairline());
        var tournament = new StackPanel { Spacing = 3 };
        tournament.Children.Add(Ui.Text("TOURNAMENT", 8, FontWeight.Black, Ui.Brush(Palette.Secondary)));
        tournament.Children.Add(Ui.Text(_store.UserTournamentStatus, 12, FontWeight.SemiBold, wrapping: TextWrapping.Wrap));
        stack.Children.Add(tournament);
        return Ui.Card(stack, 20);
    }

    private static Control StatusRow(string label, string value, Color tint)
    {
        var row = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*,Auto") };
        row.Children.Add(new Border
        {
            Width = 6,
            Height = 6,
            CornerRadius = new CornerRadius(3),
            Background = Ui.Brush(tint),
            VerticalAlignment = VerticalAlignment.Center
        });
        var name = Ui.Secondary(label, 11);
        name.Margin = new Thickness(8, 0, 0, 0);
        Grid.SetColumn(name, 1);
        row.Children.Add(name);
        var text = Ui.Text(value, 12, FontWeight.SemiBold);
        text.HorizontalAlignment = HorizontalAlignment.Right;
        Grid.SetColumn(text, 2);
        row.Children.Add(text);
        return row;
    }

    private Control StandingsCard()
    {
        var stack = new StackPanel { Spacing = 8 };
        var header = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        header.Children.Add(Ui.SectionHeader(
            "League Phase Table",
            "36 clubs · 8 matches each · top 8 straight to the Round of 16"));
        var rounds = Ui.Secondary($"Simulated {_store.Season?.LeagueRoundsPlayed ?? 0} / 8 matchdays", 10);
        rounds.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(rounds, 1);
        header.Children.Add(rounds);
        stack.Children.Add(header);

        stack.Children.Add(StandingsHeader());

        var rows = new StackPanel { Spacing = 1 };
        var standings = _store.Standings;
        for (var index = 0; index < standings.Count; index++)
        {
            rows.Children.Add(StandingsRow(index + 1, standings[index]));
        }
        stack.Children.Add(rows);

        var legend = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 14 };
        legend.Children.Add(LegendDot(Palette.Green, "Round of 16"));
        legend.Children.Add(LegendDot(Palette.Gold, "Knockout playoff"));
        stack.Children.Add(legend);
        return Ui.Card(stack, 18);
    }

    private static Control StandingsHeader()
    {
        var grid = CreateStandingsGrid();
        AddStandingCell(grid, "#", 0, TextAlignment.Right, true);
        AddStandingCell(grid, "CLUB", 1, TextAlignment.Left, true);
        grid.Children[1].Margin = new Thickness(8, 0, 0, 0);
        var labels = new[] { "P", "W", "D", "L", "GF", "GA", "GD" };
        for (var index = 0; index < labels.Length; index++)
        {
            AddStandingCell(grid, labels[index], index + 2, TextAlignment.Right, true);
        }
        AddStandingCell(grid, "PTS", 9, TextAlignment.Right, true);
        grid.Margin = new Thickness(8, 4);
        return grid;
    }

    private static Grid CreateStandingsGrid()
    {
        return new Grid { ColumnDefinitions = new ColumnDefinitions("46,*,38,30,30,30,30,30,30,42") };
    }

    private static void AddStandingCell(Grid grid, string text, int column, TextAlignment alignment, bool isHeader = false)
    {
        var block = isHeader
            ? Ui.Text(text, 8, FontWeight.Black, Ui.Brush(Palette.Tertiary))
            : Ui.Text(text, 10, FontWeight.Normal, Ui.Brush(Palette.Secondary));
        block.TextAlignment = alignment;
        block.HorizontalAlignment = alignment == TextAlignment.Right ? HorizontalAlignment.Right : HorizontalAlignment.Left;
        Grid.SetColumn(block, column);
        grid.Children.Add(block);
    }

    private Control StandingsRow(int rank, StandingRow row)
    {
        var isUser = row.Club.Id == _store.State.ManagedClubID;
        var grid = CreateStandingsGrid();

        var rankStack = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 3, HorizontalAlignment = HorizontalAlignment.Right };
        var rankText = Ui.Text($"{rank}", 10, isUser ? FontWeight.Bold : FontWeight.Normal);
        rankStack.Children.Add(rankText);
        if (rank <= 24)
        {
            rankStack.Children.Add(Ui.Text(rank <= 8 ? "R16" : "PO", 6, FontWeight.Black,
                Ui.Brush(rank <= 8 ? Palette.Green : Palette.Gold)));
        }
        grid.Children.Add(rankStack);

        var clubRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 7, Margin = new Thickness(8, 0, 0, 0) };
        clubRow.Children.Add(new ClubBadgeControl(row.Club, 18));
        var name = Ui.Text(row.Club.ShortName, 11, isUser ? FontWeight.Bold : FontWeight.Normal);
        clubRow.Children.Add(name);
        if (isUser) clubRow.Children.Add(Ui.Text("YOU", 7, FontWeight.Black, Ui.Brush(Palette.Green)));
        Grid.SetColumn(clubRow, 1);
        grid.Children.Add(clubRow);

        var stats = new[]
        {
            $"{row.Played}", $"{row.Won}", $"{row.Drawn}", $"{row.Lost}",
            $"{row.GoalsFor}", $"{row.GoalsAgainst}",
            row.GoalDifference > 0 ? $"+{row.GoalDifference}" : $"{row.GoalDifference}"
        };
        for (var index = 0; index < stats.Length; index++)
        {
            AddStandingCell(grid, stats[index], index + 2, TextAlignment.Right);
        }
        var points = Ui.Text($"{row.Points}", 11, FontWeight.Bold);
        points.TextAlignment = TextAlignment.Right;
        points.HorizontalAlignment = HorizontalAlignment.Right;
        Grid.SetColumn(points, 9);
        grid.Children.Add(points);

        return new Border
        {
            Child = grid,
            Padding = new Thickness(8, 4),
            CornerRadius = new CornerRadius(7),
            Background = Ui.Brush(isUser ? Color.FromArgb(26, Palette.Green.R, Palette.Green.G, Palette.Green.B) : Colors.Transparent)
        };
    }

    private static Control LegendDot(Color color, string text)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 5 };
        row.Children.Add(new Border
        {
            Width = 6,
            Height = 6,
            CornerRadius = new CornerRadius(3),
            Background = Ui.Brush(color),
            VerticalAlignment = VerticalAlignment.Center
        });
        row.Children.Add(Ui.Secondary(text, 9));
        return row;
    }

    private Control ResultsCard()
    {
        var stack = new StackPanel { Spacing = 10 };
        stack.Children.Add(Ui.SectionHeader("Latest Results", "Click a result for the full match report"));
        foreach (var report in _store.LatestReports.Take(5))
        {
            stack.Children.Add(ResultRow(report));
        }
        return Ui.Card(stack, 18);
    }

    private Control ResultRow(MatchReport report)
    {
        var home = ClubDatabase.Club(report.HomeClubID);
        var away = ClubDatabase.Club(report.AwayClubID);
        var isUser = report.HomeClubID == _store.State.ManagedClubID || report.AwayClubID == _store.State.ManagedClubID;

        var stack = new StackPanel { Spacing = 6 };
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        if (home is not null) row.Children.Add(new ClubBadgeControl(home, 26));
        var text = new StackPanel { Spacing = 1 };
        text.Children.Add(Ui.Text($"{home?.ShortName ?? "—"} {report.Scoreline} {away?.ShortName ?? "—"}", 12, FontWeight.SemiBold));
        text.Children.Add(Ui.Secondary($"{report.Phase.DisplayName()} · {report.PlayedAt.LocalDateTime:MMM d, h:mm tt}", 9));
        row.Children.Add(text);
        if (away is not null) row.Children.Add(new ClubBadgeControl(away, 26));
        stack.Children.Add(row);
        stack.Children.Add(Ui.Secondary(report.Summary, 10, TextWrapping.Wrap));

        var card = new Border
        {
            Child = stack,
            Padding = new Thickness(12),
            CornerRadius = new CornerRadius(13),
            Background = Ui.Brush(isUser
                ? Color.FromArgb(20, Palette.Green.R, Palette.Green.G, Palette.Green.B)
                : Color.FromArgb(8, 20, 32, 27)),
            BorderBrush = Ui.Brush(Palette.Hairline),
            BorderThickness = new Thickness(1),
            Cursor = new Avalonia.Input.Cursor(Avalonia.Input.StandardCursorType.Hand)
        };
        card.PointerPressed += (_, args) =>
        {
            if (!args.GetCurrentPoint(card).Properties.IsLeftButtonPressed) return;
            var dialog = new MatchReportWindow(report, _store.State.ManagedClubID);
            _ = dialog.ShowDialog(_window);
        };
        return card;
    }

    private Control TrophyCard()
    {
        var stack = new StackPanel { Spacing = 10 };
        stack.Children.Add(Ui.SectionHeader("Trophy Cabinet",
            $"{_store.UserTitles} European title{(_store.UserTitles == 1 ? "" : "s")}"));
        var rows = new StackPanel { Spacing = 0 };
        var trophies = _store.Trophies;
        for (var index = 0; index < trophies.Count; index++)
        {
            var trophy = trophies[index];
            var row = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*,Auto") };
            row.Children.Add(Ui.Text("🏆", 13, color: Ui.Brush(trophy.UserWasChampion ? Palette.Gold : Palette.Secondary)));
            var text = new StackPanel { Spacing = 1, Margin = new Thickness(10, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
            text.Children.Add(Ui.Text($"Season {trophy.SeasonNumber} · {trophy.ChampionName}", 12, FontWeight.SemiBold));
            text.Children.Add(Ui.Secondary($"Runner-up: {trophy.RunnerUpName}", 9));
            Grid.SetColumn(text, 1);
            row.Children.Add(text);
            var pill = Ui.Pill(trophy.UserFinish.ToUpperInvariant(), trophy.UserWasChampion ? Palette.Gold : Palette.Secondary,
                trophy.UserWasChampion ? "♛" : null);
            Grid.SetColumn(pill, 2);
            pill.VerticalAlignment = VerticalAlignment.Center;
            row.Children.Add(pill);

            rows.Children.Add(new Border { Child = row, Padding = new Thickness(0, 8) });
            if (index < trophies.Count - 1) rows.Children.Add(Ui.Hairline());
        }
        stack.Children.Add(rows);
        return Ui.Card(stack, 18);
    }

    private static Control TeamBlock(Club? club, bool isUser)
    {
        var stack = new StackPanel { Spacing = 5, HorizontalAlignment = HorizontalAlignment.Center };
        if (club is not null) stack.Children.Add(new ClubBadgeControl(club, 46) { HorizontalAlignment = HorizontalAlignment.Center });
        stack.Children.Add(Ui.Text(club?.ShortName ?? "—", 12, isUser ? FontWeight.Bold : FontWeight.SemiBold));
        stack.Children.Add(Ui.Text(isUser ? "YOUR CLUB" : club?.Code ?? "", 8, FontWeight.Bold,
            Ui.Brush(isUser ? Palette.Green : Palette.Secondary)));
        return stack;
    }

    private string? BlockingReason()
    {
        if (_store.Season is null) return "There is no active season.";
        if (_store.Season.Phase == SeasonPhase.Complete) return "The season is complete.";
        if (_store.CurrentFixtures.Count == 0) return "There are no fixtures ready to simulate.";
        if (_store.UserCurrentFixture is null) return null;
        if (!_store.LineupIsComplete) return "Complete your starting XI in the Squad tab to play this match.";
        if (_store.State.AvailableMatchMinutes < GameRules.MinutesPerMatch)
        {
            return $"{_store.MinutesUntilMatch} more study minutes needed before you can play.";
        }
        return null;
    }

    private void Simulate()
    {
        try
        {
            var outcome = _store.SimulateCurrentStage();
            _error = null;
            if (outcome.UserReport is not null)
            {
                var dialog = new MatchReportWindow(outcome.UserReport, _store.State.ManagedClubID);
                _ = dialog.ShowDialog(_window);
            }
            _signature = "";
            Refresh();
        }
        catch (Exception exception)
        {
            _error = exception.Message;
            _signature = "";
            Refresh();
        }
    }

    private void StartNextSeason()
    {
        try
        {
            _store.StartNextSeason();
            _error = null;
        }
        catch (Exception exception)
        {
            _error = exception.Message;
        }
        _signature = "";
        Refresh();
    }
}
