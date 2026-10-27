using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using StudyManagerFC.Core;

namespace StudyManagerFC.Desktop;

/// <summary>
/// Modules and topics for every subject, with their own marks, averages and totals.
/// Mirrors the macOS Subjects tab.
/// </summary>
public class SubjectsView : IPage
{
    private readonly GameStore _store;
    private readonly MainWindow _window;

    private StackPanel _overviewHost = null!;
    private StackPanel _subjectHost = null!;
    private string _signature = "";

    public Control View { get; }

    public SubjectsView(GameStore store, MainWindow window)
    {
        _store = store;
        _window = window;
        View = Build();
        Refresh();
    }

    private Control Build()
    {
        var page = new StackPanel { Spacing = 22 };
        page.Children.Add(Ui.ScreenHeader(
            "Subject Tracker",
            "Modules, Marks & Averages",
            "Split every subject into the modules you are actually studying, then log marks as gained over attempted. " +
            "Past papers earn 1.5x, exam-style questions 1.25x and homework 1x, before the subject multiplier."));

        _overviewHost = new StackPanel { Spacing = 10 };
        page.Children.Add(_overviewHost);

        _subjectHost = new StackPanel { Spacing = 18 };
        page.Children.Add(_subjectHost);

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

    public void Refresh()
    {
        var signature = string.Join("|",
            _store.State.Subtopics.Count,
            _store.State.RecentSessions.Count,
            _store.State.RecentSessions.Count == 0 ? "-" : _store.State.RecentSessions[0].Id,
            _store.State.ClubCash,
            string.Join(",", _store.State.Subtopics.Select(subtopic => $"{subtopic.Id}:{subtopic.Name}")));
        if (signature == _signature) return;
        _signature = signature;
        Rebuild();
    }

    private void Rebuild()
    {
        RebuildOverview();
        _subjectHost.Children.Clear();
        foreach (var subject in StudySubjectExtensions.All)
        {
            _subjectHost.Children.Add(BuildSubjectCard(subject));
        }
    }

    private void RebuildOverview()
    {
        _overviewHost.Children.Clear();
        var overall = _store.StudyAggregate;
        var trackedSubjects = _store.State.Subtopics.Select(subtopic => subtopic.Subject).Distinct().Count();

        var tiles = new UniformGrid { Columns = 4 };
        tiles.Children.Add(Tile(
            "Marks Attempted",
            $"{overall.MarksTotal}",
            $"{overall.MarksObtained} gained across every piece",
            "▣",
            Palette.Teal));
        tiles.Children.Add(Tile(
            "Average Mark",
            overall.AveragePercentage is null ? "—" : $"{overall.AveragePercentage}%",
            overall.HasMarks ? "Weighted by marks attempted" : "Log a marked piece to see this",
            "%",
            Palette.Gold));
        tiles.Children.Add(Tile(
            "Work Completed",
            $"{overall.WorkCount}",
            $"{overall.PastPapers} papers · {overall.Homework} homework · {overall.ExamQuestions} questions",
            "🗂",
            Palette.Blue));
        tiles.Children.Add(Tile(
            "Tracked Topics",
            $"{_store.State.Subtopics.Count}",
            $"Across {trackedSubjects} subject{(trackedSubjects == 1 ? "" : "s")}",
            "📚",
            Palette.Green));
        _overviewHost.Children.Add(tiles);

        if (_store.State.Subtopics.Count == 0)
        {
            var hint = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
            hint.Children.Add(Ui.Text("💡", 12, color: Ui.Brush(Palette.Gold)));
            var text = Ui.Secondary(
                "Start by adding the modules or topics you are working through, for example \"Complex Numbers\" under Ext 2 Maths. " +
                "Every session you log can then be tagged to a topic, and its marks roll into that topic's average.",
                10,
                TextWrapping.Wrap);
            text.VerticalAlignment = VerticalAlignment.Center;
            hint.Children.Add(text);
            _overviewHost.Children.Add(new Border
            {
                Child = hint,
                Padding = new Thickness(12),
                CornerRadius = new CornerRadius(12),
                Background = Ui.Brush(Color.FromArgb(20, Palette.Gold.R, Palette.Gold.G, Palette.Gold.B))
            });
        }
    }

    private static Border Tile(string title, string value, string? subtitle, string icon, Color tint)
    {
        var tile = Ui.MetricTile(title, value, subtitle, icon, tint);
        tile.Margin = new Thickness(0, 0, 10, 0);
        return tile;
    }

    private Border BuildSubjectCard(StudySubject subject)
    {
        var aggregate = _store.Aggregate(subject);
        var topics = _store.SubtopicsFor(subject);
        var tint = GradeColor(aggregate.AveragePercentage);

        var stack = new StackPanel { Spacing = 12 };

        var header = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        var titles = new StackPanel { Spacing = 6 };
        titles.Children.Add(Ui.Text(subject.DisplayName(), 15, FontWeight.SemiBold));
        var pills = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
        pills.Children.Add(Ui.Pill($"×{Multiplier(subject.CashMultiplier())} cash", Palette.Gold, "💰"));
        pills.Children.Add(Ui.Pill($"×{Multiplier(subject.XpMultiplier())} XP", Palette.Teal, "✨"));
        titles.Children.Add(pills);
        header.Children.Add(titles);

        var averageStack = new StackPanel { Spacing = 0, HorizontalAlignment = HorizontalAlignment.Right };
        averageStack.Children.Add(Ui.Text(
            aggregate.AveragePercentage is null ? "—" : $"{aggregate.AveragePercentage}%",
            24,
            FontWeight.Bold,
            Ui.Brush(aggregate.HasMarks ? tint : Palette.Secondary)));
        averageStack.Children.Add(Ui.Secondary("AVERAGE", 8));
        Grid.SetColumn(averageStack, 1);
        header.Children.Add(averageStack);
        stack.Children.Add(header);

        stack.Children.Add(BuildStatsRow(aggregate));
        stack.Children.Add(Ui.Hairline());

        if (topics.Count == 0)
        {
            stack.Children.Add(Ui.Secondary("No topics yet — add your first module below.", 10));
        }
        else
        {
            var topicStack = new StackPanel { Spacing = 7 };
            foreach (var topic in topics)
            {
                topicStack.Children.Add(BuildTopicRow(topic, _store.AggregateForSubtopic(topic.Id)));
            }
            stack.Children.Add(topicStack);
        }

        stack.Children.Add(BuildAddRow(subject));
        return Ui.Card(stack, 16, 16);
    }

    private Control BuildStatsRow(StudyAggregate aggregate)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 18 };
        row.Children.Add(Stat("STUDY TIME", Duration(aggregate.Minutes)));
        row.Children.Add(Stat("WORK DONE", $"{aggregate.WorkCount}"));
        row.Children.Add(Stat("PAST PAPERS", $"{aggregate.PastPapers}"));
        row.Children.Add(Stat("MARKS", aggregate.HasMarks ? $"{aggregate.MarksObtained}/{aggregate.MarksTotal}" : "—"));
        return row;
    }

    private static Control Stat(string label, string value)
    {
        var stack = new StackPanel { Spacing = 1 };
        stack.Children.Add(Ui.Text(value, 13, FontWeight.Bold));
        stack.Children.Add(Ui.Text(label, 8, FontWeight.Black, Ui.Brush(Palette.Secondary)));
        return stack;
    }

    private Control BuildTopicRow(Subtopic topic, StudyAggregate aggregate)
    {
        var tint = GradeColor(aggregate.AveragePercentage);
        var content = new StackPanel { Spacing = 5 };

        var top = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,Auto,*,Auto") };
        top.Children.Add(Ui.Text(topic.Name, 12, FontWeight.SemiBold));
        var percentage = Ui.Text(
            aggregate.AveragePercentage is null ? "UNMARKED" : $"{aggregate.AveragePercentage}%",
            10,
            FontWeight.Bold,
            Ui.Brush(tint));
        percentage.Margin = new Thickness(6, 0, 0, 0);
        Grid.SetColumn(percentage, 1);
        top.Children.Add(percentage);
        var summary = Ui.Secondary(TopicSummary(aggregate), 9);
        summary.HorizontalAlignment = HorizontalAlignment.Right;
        Grid.SetColumn(summary, 2);
        top.Children.Add(summary);

        var delete = new ActionButton("🗑", Colors.Transparent, Palette.Secondary, radius: 8,
            padding: new Thickness(6, 2), fontSize: 10);
        delete.Clicked += async () => await ConfirmDelete(topic);
        delete.Margin = new Thickness(8, 0, 0, 0);
        Grid.SetColumn(delete, 3);
        top.Children.Add(delete);
        content.Children.Add(top);

        var bar = new ReadinessBar(4, tint) { Progress = aggregate.AverageRatio ?? 0 };
        content.Children.Add(bar);

        return new Border
        {
            Child = content,
            Padding = new Thickness(10, 8),
            CornerRadius = new CornerRadius(10),
            Background = Ui.Brush(Color.FromArgb(12, Palette.Ink.R, Palette.Ink.G, Palette.Ink.B))
        };
    }

    private Control BuildAddRow(StudySubject subject)
    {
        var row = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        var input = new TextBox { Watermark = "Add a module or topic" };
        row.Children.Add(input);

        var add = new ActionButton("＋  Add", Palette.Green, Colors.White, radius: 9,
            padding: new Thickness(12, 6), fontSize: 11);
        add.Margin = new Thickness(8, 0, 0, 0);
        Grid.SetColumn(add, 1);
        row.Children.Add(add);

        void Submit()
        {
            if (_store.AddSubtopic(input.Text ?? "", subject) is null) return;
            input.Text = "";
        }

        add.Clicked += Submit;
        input.KeyDown += (_, args) =>
        {
            if (args.Key != Key.Enter) return;
            Submit();
            args.Handled = true;
        };
        return row;
    }

    private async Task ConfirmDelete(Subtopic topic)
    {
        var subject = topic.Subject;
        var dialog = new ConfirmWindow(
            $"Delete {topic.Name}?",
            $"Sessions you already logged stay in your history and in the {subject.ShortName()} totals, but the topic leaves this list.",
            "Delete");
        var confirmed = await _window.ShowDialog<bool>(dialog);
        if (confirmed) _store.DeleteSubtopic(topic.Id);
    }

    private static string TopicSummary(StudyAggregate aggregate)
    {
        var parts = new List<string>();
        if (aggregate.HasMarks) parts.Add($"{aggregate.MarksObtained}/{aggregate.MarksTotal} marks");
        if (aggregate.PastPapers > 0) parts.Add($"{aggregate.PastPapers} paper{(aggregate.PastPapers == 1 ? "" : "s")}");
        if (aggregate.Minutes > 0) parts.Add(Duration(aggregate.Minutes));
        return parts.Count == 0 ? "No work logged" : string.Join(" · ", parts);
    }

    private static Color GradeColor(int? percentage) => percentage switch
    {
        null => Palette.Secondary,
        >= 85 => Palette.Green,
        >= 70 => Palette.Teal,
        >= 55 => Palette.Gold,
        _ => Palette.Orange
    };

    private static string Duration(int minutes)
    {
        if (minutes <= 0) return "0m";
        var hours = minutes / 60;
        var remainder = minutes % 60;
        if (hours > 0 && remainder > 0) return $"{hours}h {remainder}m";
        return hours > 0 ? $"{hours}h" : $"{remainder}m";
    }

    private static string Multiplier(double value) => value.ToString("0.##");
}
