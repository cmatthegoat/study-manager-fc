using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Layout;
using Avalonia.Media;
using StudyManagerFC.Core;

namespace StudyManagerFC.Desktop;

public class DashboardView : IPage
{
    private readonly GameStore _store;
    private readonly MainWindow _window;

    private TextBlock _timerText = null!;
    private TextBlock _statusText = null!;
    private Border _statusDot = null!;
    private ActionButton _startPause = null!;
    private ActionButton _resetTimer = null!;
    private TextBlock _lastSession = null!;
    private TextBlock _timerButtonCaption = null!;

    private SegmentedControl _activity = null!;
    private ComboBox _subject = null!;
    private ComboBox _topic = null!;
    private List<Subtopic> _topicOptions = [];
    private string _topicSignature = "";
    private TextBox _title = null!;
    private TextBox _marksObtained = null!;
    private TextBox _marksTotal = null!;
    private StackPanel _marksRow = null!;
    private TextBlock _marksHint = null!;
    private Stepper _quantity = null!;
    private Stepper _minutes = null!;
    private TextBlock _rewardPreview = null!;
    private StudyActivityKind _kind = StudyActivityKind.Homework;

    private TextBlock _readinessValue = null!;
    private ReadinessBar _readinessBar = null!;
    private TextBlock _readinessTitle = null!;
    private TextBlock _readinessSubtitle = null!;
    private ContentControl _nextMatchHost = null!;
    private ContentControl _bankHost = null!;

    private TextBlock _cashValue = null!;
    private TextBlock _cashSubtitle = null!;
    private TextBlock _levelValue = null!;
    private TextBlock _levelSubtitle = null!;
    private TextBlock _studyValue = null!;
    private TextBlock _studySubtitle = null!;
    private TextBlock _streakValue = null!;
    private TextBlock _streakSubtitle = null!;
    private TextBlock _homeworkValue = null!;
    private TextBlock _examValue = null!;
    private TextBlock _examSubtitle = null!;

    private StackPanel _sessionsHost = null!;
    private ActionButton _viewAllLog = null!;
    private string _sessionSignature = "";
    private string _nextFixtureSignature = "";

    public Control View { get; }

    public DashboardView(GameStore store, MainWindow window)
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
            $"Season {_store.State.SeasonNumber} · Level {_store.Level}",
            "Study Dashboard",
            "Every minute builds your club. Log study time to unlock the next Champions League match."));

        var columns = new Grid { ColumnDefinitions = new ColumnDefinitions("*,350") };
        var left = new StackPanel { Spacing = 18 };
        left.Children.Add(BuildTimerCard());
        left.Children.Add(BuildQuickLogCard());

        var right = new StackPanel { Spacing = 18, Margin = new Thickness(18, 0, 0, 0) };
        right.Children.Add(BuildReadinessCard());
        right.Children.Add(BuildStatsGrid());

        columns.Children.Add(left);
        Grid.SetColumn(right, 1);
        columns.Children.Add(right);
        page.Children.Add(columns);
        page.Children.Add(BuildSessionsCard());

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

    private Control BuildTimerCard()
    {
        var stack = new StackPanel { Spacing = 18 };

        var header = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        var titles = new StackPanel { Spacing = 3 };
        titles.Children.Add(Ui.Text("FOCUS TIMER", 10, FontWeight.Black, Ui.Brush(Color.FromArgb(178, 255, 255, 255))));
        titles.Children.Add(Ui.Text("One minute, one step forward", 16, FontWeight.SemiBold, Ui.Brush(Colors.White)));
        header.Children.Add(titles);

        _statusDot = new Border
        {
            Width = 7,
            Height = 7,
            CornerRadius = new CornerRadius(4),
            Background = Ui.Brush(Colors.White),
            VerticalAlignment = VerticalAlignment.Center
        };
        _statusText = Ui.Text("READY", 9, FontWeight.Black, Ui.Brush(Color.FromArgb(190, 255, 255, 255)));
        var statusRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6, VerticalAlignment = VerticalAlignment.Center };
        statusRow.Children.Add(_statusDot);
        statusRow.Children.Add(_statusText);
        var statusPill = new Border
        {
            Child = statusRow,
            Padding = new Thickness(9, 6),
            CornerRadius = new CornerRadius(999),
            Background = Ui.Brush(Color.FromArgb(28, 255, 255, 255)),
            VerticalAlignment = VerticalAlignment.Top
        };
        Grid.SetColumn(statusPill, 1);
        header.Children.Add(statusPill);
        stack.Children.Add(header);

        _timerText = new TextBlock
        {
            Text = "00:00",
            FontSize = 60,
            FontWeight = FontWeight.Black,
            FontFamily = Ui.Family,
            Foreground = Ui.Brush(Colors.White),
            HorizontalAlignment = HorizontalAlignment.Center,
            TextAlignment = TextAlignment.Center
        };
        stack.Children.Add(_timerText);

        _startPause = new ActionButton(
            "▶  Start Focus Timer",
            Colors.White,
            Palette.Ink,
            radius: 10,
            padding: new Thickness(14, 10),
            fontSize: 12,
            align: HorizontalAlignment.Stretch);
        _startPause.Clicked += ToggleTimer;
        _timerButtonCaption = Ui.Text("", 9, color: Ui.Brush(Color.FromArgb(170, 255, 255, 255)));
        _resetTimer = new ActionButton("✕", Color.FromArgb(24, 255, 255, 255), Colors.White, radius: 10,
            padding: new Thickness(13, 10), fontSize: 11);
        _resetTimer.Clicked += () => _store.ResetTimer();

        var buttons = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        buttons.Children.Add(_startPause);
        Grid.SetColumn(_resetTimer, 1);
        _resetTimer.Margin = new Thickness(10, 0, 0, 0);
        buttons.Children.Add(_resetTimer);
        stack.Children.Add(buttons);

        var legend = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 16 };
        foreach (var text in new[] { "💰 10 cash / min", "✨ 6 XP / min", "⏱ 1 min toward match" })
        {
            legend.Children.Add(Ui.Text(text, 9, color: Ui.Brush(Color.FromArgb(175, 255, 255, 255))));
        }
        stack.Children.Add(legend);

        _lastSession = Ui.Text("", 10, color: Ui.Brush(Color.FromArgb(170, 255, 255, 255)));
        stack.Children.Add(_lastSession);

        var card = new Border
        {
            Child = stack,
            Padding = new Thickness(22),
            CornerRadius = new CornerRadius(22),
            Background = new LinearGradientBrush
            {
                StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
                EndPoint = new RelativePoint(1, 1, RelativeUnit.Relative),
                GradientStops =
                {
                    new GradientStop(Color.Parse("#1D6A48"), 0),
                    new GradientStop(Color.Parse("#12372D"), 1)
                }
            },
            BorderBrush = Ui.Brush(Color.FromArgb(31, 255, 255, 255)),
            BorderThickness = new Thickness(1)
        };
        return card;
    }

    private Control BuildQuickLogCard()
    {
        var stack = new StackPanel { Spacing = 14 };
        stack.Children.Add(Ui.SectionHeader("Log Study", "Homework, past papers, or exam-style questions"));

        _activity = new SegmentedControl(
            StudyActivityKindExtensions.All.Select(kind => kind.Title()),
            width: double.NaN);
        _activity.SelectionChanged += index =>
        {
            _kind = StudyActivityKindExtensions.All[index];
            UpdateActivity();
        };
        stack.Children.Add(_activity);

        var row = new Grid { ColumnDefinitions = new ColumnDefinitions("155,195,*") };
        _subject = new ComboBox
        {
            ItemsSource = StudySubjectExtensions.All.Select(subject => subject.ShortName()).ToList(),
            SelectedIndex = 1
        };
        _subject.SelectionChanged += (_, _) =>
        {
            RebuildTopics();
            UpdateRewardPreview();
        };
        row.Children.Add(_subject);

        _topic = new ComboBox { IsEnabled = false };
        _topic.Margin = new Thickness(8, 0, 0, 0);
        _topic.SelectionChanged += (_, _) => UpdateRewardPreview();
        Grid.SetColumn(_topic, 1);
        row.Children.Add(_topic);

        _title = new TextBox { Watermark = "What did you work on?" };
        _title.Margin = new Thickness(8, 0, 0, 0);
        Grid.SetColumn(_title, 2);
        row.Children.Add(_title);
        stack.Children.Add(row);

        _marksRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        _marksRow.Children.Add(Ui.Secondary("Marks", 11));
        _marksObtained = new TextBox { Watermark = "Gained", Width = 70 };
        _marksTotal = new TextBox { Watermark = "Attempted", Width = 80 };
        _marksObtained.TextChanged += (_, _) => UpdateRewardPreview();
        _marksTotal.TextChanged += (_, _) => UpdateRewardPreview();
        _marksRow.Children.Add(_marksObtained);
        _marksRow.Children.Add(Ui.Secondary("/", 12));
        _marksRow.Children.Add(_marksTotal);
        _marksHint = Ui.Secondary("Gained / attempted — the percentage sets your rate", 9);
        _marksRow.Children.Add(_marksHint);
        stack.Children.Add(_marksRow);

        var steppers = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        _quantity = new Stepper(1, "assignments", 1, 10);
        _quantity.ValueChanged += _ => UpdateRewardPreview();
        steppers.Children.Add(_quantity);

        _minutes = new Stepper(30, "minutes", 5, 240, 5);
        _minutes.ValueChanged += _ => UpdateRewardPreview();
        _minutes.HorizontalAlignment = HorizontalAlignment.Right;
        Grid.SetColumn(_minutes, 1);
        steppers.Children.Add(_minutes);
        stack.Children.Add(steppers);

        _rewardPreview = Ui.Secondary("", 10);
        stack.Children.Add(_rewardPreview);

        var logButton = new ActionButton(
            "✓  Log Study Session",
            Palette.Green,
            Colors.White,
            radius: 10,
            padding: new Thickness(14, 8),
            fontSize: 12,
            align: HorizontalAlignment.Stretch);
        logButton.Clicked += LogSession;
        stack.Children.Add(logButton);

        UpdateActivity();
        RebuildTopics();
        return Ui.Card(stack, 20);
    }

    private StudySubject SelectedSubject => StudySubjectExtensions.All[Math.Max(0, _subject.SelectedIndex)];

    private Guid? SelectedSubtopicId
    {
        get
        {
            var index = _topic.SelectedIndex - 1;
            return index >= 0 && index < _topicOptions.Count ? _topicOptions[index].Id : null;
        }
    }

    /// <summary>Keeps the topic picker in step with the chosen subject and the saved topics.</summary>
    private void RebuildTopics(bool preserveSelection = false)
    {
        var subject = SelectedSubject;
        _topicOptions = _store.SubtopicsFor(subject);
        _topicSignature = TopicsSignature(subject);

        var names = new List<string> { _topicOptions.Count == 0 ? "No topics yet" : "Whole subject" };
        names.AddRange(_topicOptions.Select(topic => topic.Name));
        var previous = preserveSelection ? _topic.SelectedIndex : 0;
        _topic.ItemsSource = names;
        _topic.SelectedIndex = Math.Clamp(previous, 0, names.Count - 1);
        _topic.IsEnabled = _topicOptions.Count > 0;
    }

    private string TopicsSignature(StudySubject subject) =>
        subject + ":" + string.Join(",", _store.SubtopicsFor(subject).Select(topic => $"{topic.Id}:{topic.Name}"));

    private Control BuildReadinessCard()
    {
        var stack = new StackPanel { Spacing = 14 };
        var header = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        header.Children.Add(Ui.SectionHeader("Match Readiness", "The 90-minute rule"));
        _readinessValue = Ui.Text("0 / 90", 12, FontWeight.Bold, Ui.Brush(Palette.Secondary));
        Grid.SetColumn(_readinessValue, 1);
        _readinessValue.VerticalAlignment = VerticalAlignment.Center;
        header.Children.Add(_readinessValue);
        stack.Children.Add(header);

        _readinessBar = new ReadinessBar(12);
        stack.Children.Add(_readinessBar);

        var statusRow = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        var text = new StackPanel { Spacing = 2 };
        _readinessTitle = Ui.Text("", 16, FontWeight.Bold);
        _readinessSubtitle = Ui.Secondary("", 10);
        text.Children.Add(_readinessTitle);
        text.Children.Add(_readinessSubtitle);
        statusRow.Children.Add(text);
        _bankHost = new ContentControl { VerticalAlignment = VerticalAlignment.Center };
        Grid.SetColumn(_bankHost, 1);
        statusRow.Children.Add(_bankHost);
        stack.Children.Add(statusRow);

        stack.Children.Add(Ui.Hairline());
        _nextMatchHost = new ContentControl();
        stack.Children.Add(_nextMatchHost);

        return Ui.Card(stack, 20);
    }

    private Control BuildStatsGrid()
    {
        var grid = new UniformGrid { Columns = 2 };
        grid.Children.Add(StatTile("Club Cash", "💰", Palette.Gold, out _cashValue, out _cashSubtitle));
        grid.Children.Add(StatTile("Level", "⚡", Palette.Teal, out _levelValue, out _levelSubtitle));
        grid.Children.Add(StatTile("Total Study", "⏳", Palette.Green, out _studyValue, out _studySubtitle));
        grid.Children.Add(StatTile("Study Streak", "🔥", Color.Parse("#E08A34"), out _streakValue, out _streakSubtitle));
        grid.Children.Add(StatTile("Homework", "📚", Palette.Blue, out _homeworkValue, out _));
        grid.Children.Add(StatTile("Exam Practice", "📝", Palette.Purple, out _examValue, out _examSubtitle));
        return grid;
    }

    private static Border StatTile(string title, string icon, Color tint, out TextBlock value, out TextBlock subtitle)
    {
        var stack = new StackPanel { Spacing = 8 };
        var iconRow = new StackPanel { Orientation = Orientation.Horizontal };
        iconRow.Children.Add(Ui.IconCircle(icon, tint, 26, 11));
        stack.Children.Add(iconRow);
        value = Ui.Text("", 21, FontWeight.Bold);
        stack.Children.Add(value);
        var labels = new StackPanel { Spacing = 1 };
        labels.Children.Add(Ui.Text(title, 11, FontWeight.SemiBold));
        subtitle = Ui.Secondary("", 9);
        labels.Children.Add(subtitle);
        stack.Children.Add(labels);
        var card = Ui.Card(stack, 13, 15);
        card.Margin = new Thickness(0, 0, 8, 8);
        return card;
    }

    private Control BuildSessionsCard()
    {
        var stack = new StackPanel { Spacing = 12 };
        var header = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        header.Children.Add(Ui.SectionHeader("Recent Study", "Your latest logged sessions"));
        _viewAllLog = new ActionButton(
            "View all",
            Palette.SurfaceTint,
            Palette.Green,
            Palette.Hairline,
            radius: 999,
            padding: new Thickness(12, 5),
            fontSize: 11,
            align: HorizontalAlignment.Right);
        _viewAllLog.VerticalAlignment = VerticalAlignment.Center;
        _viewAllLog.Clicked += () => _window.Navigate(MainSection.StudyLog);
        Grid.SetColumn(_viewAllLog, 1);
        header.Children.Add(_viewAllLog);
        stack.Children.Add(header);
        _sessionsHost = new StackPanel { Spacing = 0 };
        stack.Children.Add(_sessionsHost);
        return Ui.Card(stack, 20);
    }

    private void ToggleTimer()
    {
        if (_store.IsTimerRunning) _store.PauseTimer();
        else _store.StartTimer();
    }

    private void UpdateActivity()
    {
        _marksRow.IsVisible = _kind.SupportsMarking();
        _quantity.Maximum = _kind == StudyActivityKind.ExamQuestions ? 100 : _kind == StudyActivityKind.FocusSession ? 1 : 10;
        _quantity.Value = 1;
        _quantity.Reset(1);
        UpdateRewardPreview();
    }

    private void UpdateRewardPreview()
    {
        var subject = SelectedSubject;
        var marksObtained = int.TryParse(_marksObtained.Text, out var got) ? got : (int?)null;
        var marksTotal = int.TryParse(_marksTotal.Text, out var total) ? total : (int?)null;
        var (cash, xp, ratio) = StudyReward.Calculate(_kind, subject, _minutes.Value, marksObtained, marksTotal);

        var parts = new List<string>();
        if (_kind.RewardMultiplier() != 1) parts.Add($"{_kind.Title()} rate ×{_kind.RewardMultiplier():0.##}");
        parts.Add($"+{cash} Club Cash");
        parts.Add($"+{xp} XP");
        if (ratio.HasValue)
        {
            var percentage = (int)Math.Round(ratio.Value * 100, MidpointRounding.AwayFromZero);
            parts.Add($"{marksObtained}/{marksTotal} · {percentage}%");
        }
        parts.Add($"{_minutes.Value} min toward next match");
        _rewardPreview.Text = string.Join(" · ", parts);
        _marksHint.Text = ratio.HasValue
            ? "The percentage sets your rate"
            : "Gained / attempted — the percentage sets your rate";
    }

    private void LogSession()
    {
        var subject = SelectedSubject;
        int? marksObtained = _kind.SupportsMarking() && int.TryParse(_marksObtained.Text, out var got) ? got : null;
        int? marksTotal = _kind.SupportsMarking() && int.TryParse(_marksTotal.Text, out var total) ? total : null;
        _store.LogStudy(_kind, _title.Text ?? "", _minutes.Value, _quantity.Value, subject, marksObtained, marksTotal, SelectedSubtopicId);
        _title.Text = "";
        _marksObtained.Text = "";
        _marksTotal.Text = "";
        _quantity.Reset(1);
    }

    public void Refresh()
    {
        var minutes = _store.TimerElapsedSeconds / 60;
        var seconds = _store.TimerElapsedSeconds % 60;
        _timerText.Text = $"{minutes:00}:{seconds:00}";
        _statusText.Text = _store.IsTimerRunning ? "RUNNING" : "READY";
        _statusDot.Background = Ui.Brush(_store.IsTimerRunning ? Palette.Gold : Color.FromArgb(110, 255, 255, 255));
        _startPause.Text = _store.IsTimerRunning ? "❚❚  Pause & Log" : "▶  Start Focus Timer";
        _resetTimer.IsVisible = _store.IsTimerRunning || _store.TimerElapsedSeconds > 0;
        _lastSession.Text = _store.LastTimerSessionMinutes > 0 && !_store.IsTimerRunning
            ? $"Last session logged: {_store.LastTimerSessionMinutes} minutes"
            : "";

        var ready = _store.State.AvailableMatchMinutes >= GameRules.MinutesPerMatch;
        _readinessValue.Text = $"{Math.Min(_store.State.AvailableMatchMinutes, 90)} / 90";
        _readinessValue.Foreground = Ui.Brush(ready ? Palette.Green : Palette.Secondary);
        _readinessBar.Progress = _store.MatchReadiness;
        if (ready)
        {
            _readinessTitle.Text = "Match unlocked";
            _readinessTitle.Foreground = Ui.Brush(Palette.Green);
            _readinessSubtitle.Text = "Open the Champions League hub to simulate.";
        }
        else
        {
            _readinessTitle.Text = $"{_store.MinutesUntilMatch} minutes to unlock";
            _readinessTitle.Foreground = Ui.Brush(Palette.Ink);
            _readinessSubtitle.Text = "Logged study minutes carry across matches.";
        }

        _bankHost.Content = _store.State.AvailableMatchMinutes > 90
            ? Ui.Pill($"BANK {_store.State.AvailableMatchMinutes}m", Palette.Gold, "▤")
            : null;

        _cashValue.Text = _store.State.ClubCash.ToString("N0");
        _cashSubtitle.Text = "Available to spend";
        _levelValue.Text = $"{_store.XpIntoLevel} / {GameRules.XpPerLevel} XP";
        _levelSubtitle.Text = $"{_store.State.Xp:N0} lifetime XP";
        _studyValue.Text = $"{_store.State.Study.TotalStudyMinutes / 60}h {_store.State.Study.TotalStudyMinutes % 60}m";
        _studySubtitle.Text = $"{_store.State.Study.TotalSessions} sessions logged";
        _streakValue.Text = $"{_store.State.Study.CurrentStreak} days";
        _streakSubtitle.Text = $"Best: {_store.State.Study.BestStreak} days";
        _homeworkValue.Text = $"{_store.State.Study.HomeworkCompleted}";
        _examValue.Text = $"{_store.State.Study.PastPapersCompleted}";
        _examSubtitle.Text = $"{_store.State.Study.ExamQuestionsSolved} questions solved";

        var fixtureSignature = $"{_store.NextFixtureForUser?.Id}-{_store.IsSeasonComplete}-{_store.State.AvailableMatchMinutes}";
        if (fixtureSignature != _nextFixtureSignature)
        {
            _nextFixtureSignature = fixtureSignature;
            BuildNextMatch();
        }

        if (TopicsSignature(SelectedSubject) != _topicSignature) RebuildTopics(preserveSelection: true);

        var signature = string.Join("|", _store.State.RecentSessions.Take(8).Select(session => session.Id));
        if (signature != _sessionSignature)
        {
            _sessionSignature = signature;
            BuildSessions();
        }
    }

    private void BuildNextMatch()
    {
        var fixture = _store.NextFixtureForUser;
        var club = _store.ManagedClub;
        if (fixture is null || club is null)
        {
            _nextMatchHost.Content = Ui.Secondary(
                _store.IsSeasonComplete
                    ? "Season complete. Your trophy cabinet is waiting."
                    : "No fixture currently scheduled.",
                10,
                TextWrapping.Wrap);
            return;
        }

        var opponentId = fixture.HomeClubID == club.Id ? fixture.AwayClubID : fixture.HomeClubID;
        var opponent = ClubDatabase.Club(opponentId);
        var row = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*,Auto") };
        if (opponent is not null) row.Children.Add(new ClubBadgeControl(opponent, 38));

        var text = new StackPanel { Spacing = 1, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(10, 0, 0, 0) };
        text.Children.Add(Ui.Text("NEXT MATCH", 8, FontWeight.Black, Ui.Brush(Palette.Secondary)));
        text.Children.Add(Ui.Text(
            $"{(fixture.HomeClubID == club.Id ? "vs" : "away at")} {opponent?.ShortName ?? "TBD"}",
            13,
            FontWeight.SemiBold));
        text.Children.Add(Ui.Secondary(
            fixture.Phase == SeasonPhase.League ? $"Matchday {fixture.Round}" : fixture.Phase.DisplayName(), 9));
        Grid.SetColumn(text, 1);
        row.Children.Add(text);

        var badge = new ClubBadgeControl(club, 38);
        Grid.SetColumn(badge, 2);
        row.Children.Add(badge);

        _nextMatchHost.Content = new Border
        {
            Child = row,
            Padding = new Thickness(10),
            CornerRadius = new CornerRadius(12),
            Background = Ui.Brush(Color.FromArgb(14, 20, 32, 27))
        };
    }

    private void BuildSessions()
    {
        _sessionsHost.Children.Clear();
        var all = _store.State.RecentSessions;
        var sessions = all.Take(8).ToList();
        _viewAllLog.Text = all.Count > 8 ? $"View all {all.Count}" : "Open log";
        if (sessions.Count == 0)
        {
            var empty = new StackPanel { Spacing = 8, HorizontalAlignment = HorizontalAlignment.Center };
            empty.Children.Add(Ui.Text("⏱", 26, color: Ui.Brush(Palette.Green), wrapping: TextWrapping.NoWrap));
            empty.Children.Add(Ui.Text("No study logged yet", 14, FontWeight.SemiBold));
            var message = Ui.Secondary(
                "Start the timer or log a session above. Your first 90 minutes unlocks a Champions League match.",
                11,
                TextWrapping.Wrap);
            message.TextAlignment = TextAlignment.Center;
            message.MaxWidth = 340;
            empty.Children.Add(message);
            empty.Margin = new Thickness(0, 20);
            _sessionsHost.Children.Add(empty);
            return;
        }

        for (var index = 0; index < sessions.Count; index++)
        {
            var session = sessions[index];
            var row = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*,Auto,Auto") };
            row.Children.Add(Ui.IconCircle(session.Kind == StudyActivityKind.PastPaper ? "📄" : session.Kind == StudyActivityKind.Homework ? "📚" : session.Kind == StudyActivityKind.ExamQuestions ? "📝" : "⏱", Palette.Green));

            var text = new StackPanel { Spacing = 2, Margin = new Thickness(12, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
            text.Children.Add(Ui.Text(session.Title, 12, FontWeight.SemiBold));
            var detail = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
            detail.Children.Add(Ui.Secondary(SessionDetail(session), 9));
            if (session.MarkFraction is not null && session.Percentage is not null)
            {
                detail.Children.Add(Ui.Pill($"{session.MarkFraction} · {session.Percentage}%", Palette.Teal));
            }
            text.Children.Add(detail);
            Grid.SetColumn(text, 1);
            row.Children.Add(text);

            var minutes = Ui.Text($"{session.Minutes} min", 11, FontWeight.SemiBold);
            minutes.Margin = new Thickness(8, 0);
            Grid.SetColumn(minutes, 2);
            row.Children.Add(minutes);

            var cash = Ui.Text($"+{session.CashEarned}", 10, FontWeight.Bold, Ui.Brush(Palette.Gold));
            cash.Width = 50;
            cash.TextAlignment = TextAlignment.Right;
            Grid.SetColumn(cash, 3);
            row.Children.Add(cash);

            var padded = new Border { Child = row, Padding = new Thickness(0, 8) };
            _sessionsHost.Children.Add(padded);
            if (index < sessions.Count - 1) _sessionsHost.Children.Add(Ui.Hairline());
        }
    }

    private static string SessionDetail(StudySession session)
    {
        var parts = new List<string> { session.Kind.Title() };
        if (session.Subject.HasValue) parts.Add(session.Subject.Value.ShortName());
        if (!string.IsNullOrEmpty(session.SubtopicName)) parts.Add(session.SubtopicName!);
        parts.Add(session.Date.LocalDateTime.ToString("MMM d, h:mm tt"));
        return string.Join(" · ", parts);
    }
}
