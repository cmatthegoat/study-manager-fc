using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Layout;
using Avalonia.Media;
using StudyManagerFC.Core;

namespace StudyManagerFC.Desktop;

/// <summary>
/// Every study entry ever logged, with search across titles, subjects, topics, activity
/// kinds and marks, plus subject / kind / period filters. Mirrors the macOS Study Log tab.
/// </summary>
public class StudyLogView : IPage
{
    private readonly GameStore _store;
    private readonly MainWindow _window;

    private TextBox _search = null!;
    private ComboBox _subject = null!;
    private ComboBox _kind = null!;
    private ComboBox _period = null!;
    private StackPanel _summaryHost = null!;
    private TextBlock _countLabel = null!;
    private StackPanel _listHost = null!;

    private string _signature = "";

    private enum LogPeriod
    {
        AllTime,
        Last7,
        Last30,
        Last90
    }

    private static readonly (LogPeriod Period, string Title)[] Periods =
    [
        (LogPeriod.AllTime, "All time"),
        (LogPeriod.Last7, "Last 7 days"),
        (LogPeriod.Last30, "Last 30 days"),
        (LogPeriod.Last90, "Last 90 days")
    ];

    public Control View { get; }

    public StudyLogView(GameStore store, MainWindow window)
    {
        _store = store;
        _window = window;
        View = Build();
        Refresh();
    }

    private Control Build()
    {
        var page = new StackPanel { Spacing = 20 };
        page.Children.Add(Ui.ScreenHeader(
            "Study Log",
            "Every Entry You've Logged",
            "Search your whole history by title, subject, topic, activity or marks, then narrow it by subject, kind or date."));

        _summaryHost = new StackPanel { Spacing = 10 };
        page.Children.Add(_summaryHost);
        page.Children.Add(BuildSearchCard());

        _listHost = new StackPanel { Spacing = 14 };
        page.Children.Add(_listHost);

        var content = new Border
        {
            Padding = new Thickness(28),
            Child = page,
            MaxWidth = 1300,
            HorizontalAlignment = HorizontalAlignment.Center
        };
        return new ScrollViewer
        {
            Content = content,
            HorizontalScrollBarVisibility = Avalonia.Controls.Primitives.ScrollBarVisibility.Disabled
        };
    }

    private Control BuildSearchCard()
    {
        var stack = new StackPanel { Spacing = 12 };

        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        _search = new TextBox
        {
            Watermark = "Search entries — title, subject, topic, marks…",
            Width = 340
        };
        _search.TextChanged += (_, _) => Reload();
        row.Children.Add(_search);

        _subject = new ComboBox
        {
            ItemsSource = new List<string> { "All subjects" }
                .Concat(StudySubjectExtensions.All.Select(subject => subject.ShortName()))
                .ToList(),
            SelectedIndex = 0,
            Width = 150
        };
        _subject.SelectionChanged += (_, _) => Reload();
        row.Children.Add(_subject);

        _kind = new ComboBox
        {
            ItemsSource = new List<string> { "All activity", "Homework", "Past Paper", "Exam Questions", "Focus Session" },
            SelectedIndex = 0,
            Width = 160
        };
        _kind.SelectionChanged += (_, _) => Reload();
        row.Children.Add(_kind);

        _period = new ComboBox
        {
            ItemsSource = Periods.Select(period => period.Title).ToList(),
            SelectedIndex = 0,
            Width = 130
        };
        _period.SelectionChanged += (_, _) => Reload();
        row.Children.Add(_period);

        _countLabel = Ui.Secondary("", 11);
        row.Children.Add(_countLabel);

        var clear = new ActionButton(
            "Clear",
            Palette.SurfaceTint,
            Palette.Ink,
            Palette.Hairline,
            radius: 999,
            padding: new Thickness(14, 6),
            fontSize: 11);
        clear.Clicked += () =>
        {
            _search.Text = "";
            _subject.SelectedIndex = 0;
            _kind.SelectedIndex = 0;
            _period.SelectedIndex = 0;
            Reload();
        };
        row.Children.Add(clear);

        stack.Children.Add(Ui.SectionHeader("Search & Filters", "Everything is matched as you type"));
        stack.Children.Add(row);
        return Ui.Card(stack, 16);
    }

    public void Refresh()
    {
        var signature = string.Join("|",
            _store.State.RecentSessions.Count,
            _store.State.RecentSessions.Count == 0 ? "-" : _store.State.RecentSessions[0].Id,
            _store.State.RecentSessions.Sum(session => session.Minutes),
            _store.State.RecentSessions.Sum(session => session.CashEarned));
        if (signature == _signature) return;
        _signature = signature;
        Reload();
    }

    private void Reload()
    {
        var all = _store.State.RecentSessions;
        var filtered = Filter(all);
        RebuildSummary(filtered, all.Count);
        RebuildList(filtered, all.Count);
    }

    private List<StudySession> Filter(IReadOnlyList<StudySession> sessions)
    {
        var query = (_search?.Text ?? "").Trim();
        var subjectIndex = _subject?.SelectedIndex ?? 0;
        var kindIndex = _kind?.SelectedIndex ?? 0;
        var period = Periods[Math.Clamp(_period?.SelectedIndex ?? 0, 0, Periods.Length - 1)].Period;
        StudySubject? subject = subjectIndex > 0 ? StudySubjectExtensions.All[subjectIndex - 1] : null;
        StudyActivityKind? kind = kindIndex > 0 ? (StudyActivityKind)(kindIndex - 1) : null;
        var cutoff = period switch
        {
            LogPeriod.Last7 => DateTimeOffset.Now.AddDays(-7),
            LogPeriod.Last30 => DateTimeOffset.Now.AddDays(-30),
            LogPeriod.Last90 => DateTimeOffset.Now.AddDays(-90),
            _ => (DateTimeOffset?)null
        };

        return sessions
            .Where(session => subject is null || session.Subject == subject)
            .Where(session => kind is null || session.Kind == kind)
            .Where(session => cutoff is null || session.Date >= cutoff)
            .Where(session => query.Length == 0 || Matches(session, query))
            .OrderByDescending(session => session.Date)
            .ToList();
    }

    private void RebuildSummary(List<StudySession> filtered, int total)
    {
        _summaryHost.Children.Clear();
        var aggregate = StudyAggregate.Build(filtered);
        var tiles = new UniformGrid { Columns = 4 };
        tiles.Children.Add(Ui.MetricTile(
            "Entries",
            $"{aggregate.Sessions}",
            aggregate.Sessions == total ? "All of your history" : $"of {total} total",
            "☰",
            Palette.Green));
        tiles.Children.Add(Ui.MetricTile(
            "Minutes",
            $"{aggregate.Minutes}",
            $"{aggregate.Minutes / 60} h {aggregate.Minutes % 60} m studied",
            "⏱",
            Palette.Teal));
        tiles.Children.Add(Ui.MetricTile(
            "Club Cash",
            $"+{aggregate.CashEarned:N0}",
            "Earned on these entries",
            "◆",
            Palette.Gold));
        tiles.Children.Add(Ui.MetricTile(
            "XP",
            $"+{aggregate.XpEarned:N0}",
            aggregate.AveragePercentage is null ? "No marks recorded" : $"{aggregate.AveragePercentage}% average marks",
            "✦",
            Palette.Purple));
        _summaryHost.Children.Add(tiles);
    }

    private void RebuildList(List<StudySession> filtered, int total)
    {
        _listHost.Children.Clear();
        _countLabel.Text = $"Showing {filtered.Count} of {total} entries";

        if (total == 0)
        {
            _listHost.Children.Add(Ui.Card(EmptyState(
                "🗒",
                "Nothing logged yet",
                "Start the focus timer or quick-log a session and it will appear here, forever, searchable.")));
            return;
        }

        if (filtered.Count == 0)
        {
            _listHost.Children.Add(Ui.Card(EmptyState(
                "🔍",
                "No entries match",
                $"Try a different search term, or clear the filters to see all {total} entries.")));
            return;
        }

        foreach (var group in filtered.GroupBy(session => session.Date.LocalDateTime.Date))
        {
            _listHost.Children.Add(BuildDayCard(group.Key, group.ToList()));
        }
    }

    private Control BuildDayCard(DateTime day, List<StudySession> sessions)
    {
        var stack = new StackPanel { Spacing = 4 };
        var header = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto,Auto") };
        var title = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        title.Children.Add(Ui.Text(DayTitle(day), 14, FontWeight.SemiBold));
        title.Children.Add(Ui.Secondary($"{sessions.Count} entr{(sessions.Count == 1 ? "y" : "ies")}", 10));
        header.Children.Add(title);

        var minutes = Ui.Text($"{sessions.Sum(session => Math.Max(0, session.Minutes))} min", 11, FontWeight.SemiBold, Ui.Brush(Palette.Teal));
        Grid.SetColumn(minutes, 1);
        header.Children.Add(minutes);

        var cash = Ui.Text($"+{sessions.Sum(session => session.CashEarned):N0}", 11, FontWeight.Bold, Ui.Brush(Palette.Gold));
        cash.Margin = new Thickness(12, 0, 0, 0);
        Grid.SetColumn(cash, 2);
        header.Children.Add(cash);

        stack.Children.Add(header);
        for (var index = 0; index < sessions.Count; index++)
        {
            stack.Children.Add(BuildRow(sessions[index]));
            if (index < sessions.Count - 1) stack.Children.Add(Ui.Hairline());
        }

        return Ui.Card(stack, 16);
    }

    private Control BuildRow(StudySession session)
    {
        var row = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*,Auto,Auto,Auto,Auto,Auto") };

        row.Children.Add(Ui.IconCircle(Icon(session.Kind), Palette.Green));

        var text = new StackPanel { Spacing = 2, Margin = new Thickness(12, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
        text.Children.Add(Ui.Text(string.IsNullOrWhiteSpace(session.Title) ? session.Kind.Title() : session.Title, 12, FontWeight.SemiBold));
        var detail = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
        detail.Children.Add(Ui.Secondary(SessionDetail(session), 9));
        if (session.MarkFraction is not null && session.Percentage is not null)
        {
            detail.Children.Add(Ui.Pill($"{session.MarkFraction} · {session.Percentage}%", Palette.Teal));
        }
        text.Children.Add(detail);
        Grid.SetColumn(text, 1);
        row.Children.Add(text);

        var time = Ui.Secondary(session.Date.LocalDateTime.ToString("h:mm tt"), 10);
        time.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(time, 2);
        row.Children.Add(time);

        var minutes = Ui.Text($"{session.Minutes} min", 11, FontWeight.SemiBold);
        minutes.Margin = new Thickness(12, 0);
        minutes.VerticalAlignment = VerticalAlignment.Center;
        minutes.Width = 58;
        minutes.TextAlignment = TextAlignment.Right;
        Grid.SetColumn(minutes, 3);
        row.Children.Add(minutes);

        var xp = Ui.Text($"+{session.XpEarned} XP", 10, FontWeight.SemiBold, Ui.Brush(Palette.Purple));
        xp.Width = 70;
        xp.VerticalAlignment = VerticalAlignment.Center;
        xp.TextAlignment = TextAlignment.Right;
        Grid.SetColumn(xp, 4);
        row.Children.Add(xp);

        var cash = Ui.Text($"+{session.CashEarned}", 10, FontWeight.Bold, Ui.Brush(Palette.Gold));
        cash.Width = 56;
        cash.VerticalAlignment = VerticalAlignment.Center;
        cash.TextAlignment = TextAlignment.Right;
        Grid.SetColumn(cash, 5);
        row.Children.Add(cash);

        var id = session.Id;
        var delete = new ActionButton(
            "🗑",
            Colors.Transparent,
            Palette.Secondary,
            radius: 8,
            padding: new Thickness(8, 4),
            fontSize: 11);
        delete.Margin = new Thickness(10, 0, 0, 0);
        delete.VerticalAlignment = VerticalAlignment.Center;
        delete.Clicked += () => _store.DeleteStudySession(id);
        Grid.SetColumn(delete, 6);
        row.Children.Add(delete);

        return new Border { Child = row, Padding = new Thickness(0, 8) };
    }

    private static Control EmptyState(string icon, string title, string message)
    {
        var empty = new StackPanel { Spacing = 8, HorizontalAlignment = HorizontalAlignment.Center };
        empty.Children.Add(Ui.Text(icon, 26, color: Ui.Brush(Palette.Green), wrapping: TextWrapping.NoWrap));
        empty.Children.Add(Ui.Text(title, 14, FontWeight.SemiBold));
        var body = Ui.Secondary(message, 11, TextWrapping.Wrap);
        body.TextAlignment = TextAlignment.Center;
        body.MaxWidth = 360;
        empty.Children.Add(body);
        empty.Margin = new Thickness(0, 20);
        return empty;
    }

    private static string Icon(StudyActivityKind kind) => kind switch
    {
        StudyActivityKind.PastPaper => "📄",
        StudyActivityKind.Homework => "📚",
        StudyActivityKind.ExamQuestions => "📝",
        _ => "⏱"
    };

    private static string DayTitle(DateTime day)
    {
        var today = DateTime.Today;
        if (day == today) return "Today";
        if (day == today.AddDays(-1)) return "Yesterday";
        return day.ToString("dddd d MMMM yyyy");
    }

    private static string SessionDetail(StudySession session)
    {
        var parts = new List<string> { session.Kind.Title() };
        if (session.Subject.HasValue) parts.Add(session.Subject.Value.ShortName());
        if (!string.IsNullOrEmpty(session.SubtopicName)) parts.Add(session.SubtopicName!);
        if (session.Quantity > 1) parts.Add($"×{session.Quantity}");
        return string.Join(" · ", parts);
    }

    /// <summary>Matches everything a player might remember about an entry, not just its title.</summary>
    private static bool Matches(StudySession session, string query)
    {
        var parts = new List<string>
        {
            session.Title,
            session.Kind.Title(),
            $"{session.Minutes} min",
            $"{session.Minutes}",
            $"{session.CashEarned}",
            $"{session.XpEarned}",
            session.Date.LocalDateTime.ToString("dddd d MMMM yyyy"),
            session.Date.LocalDateTime.ToString("d MMM yyyy"),
            session.Date.LocalDateTime.ToString("h:mm tt")
        };
        if (session.Subject.HasValue)
        {
            parts.Add(session.Subject.Value.DisplayName());
            parts.Add(session.Subject.Value.ShortName());
        }
        if (!string.IsNullOrEmpty(session.SubtopicName)) parts.Add(session.SubtopicName!);
        if (session.MarkFraction is not null) parts.Add(session.MarkFraction);
        if (session.Percentage is not null) parts.Add($"{session.Percentage}%");
        return parts.Any(part => part.Contains(query, StringComparison.OrdinalIgnoreCase));
    }
}
