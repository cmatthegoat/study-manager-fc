using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using StudyManagerFC.Core;

namespace StudyManagerFC.Desktop;

public class ClubSelectionView
{
    private readonly GameStore _store;
    private readonly MainWindow _window;
    private string? _selectedClubId;
    private TextBlock _selectionName = null!;
    private TextBlock _error = null!;
    private ActionButton _startButton = null!;
    private readonly Dictionary<string, Border> _cards = [];

    public Control View { get; }

    public ClubSelectionView(GameStore store, MainWindow window)
    {
        _store = store;
        _window = window;
        View = Build();
    }

    private Control Build()
    {
        var stack = new StackPanel { Spacing = 26 };
        stack.Children.Add(Hero());

        var pots = new StackPanel { Spacing = 20 };
        var seededPots = ClubDatabase.SeededPots;
        for (var index = 0; index < seededPots.Length; index++)
        {
            var potStack = new StackPanel { Spacing = 10 };
            var labelRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12 };
            labelRow.Children.Add(Ui.Text($"POT {index + 1}", 10, FontWeight.Black, Ui.Brush(Palette.Gold)));
            labelRow.Children.Add(new Border
            {
                Height = 1,
                VerticalAlignment = VerticalAlignment.Center,
                Background = Ui.Brush(Palette.Hairline),
                Width = 420
            });
            potStack.Children.Add(labelRow);

            var grid = new WrapPanel { Orientation = Orientation.Horizontal };
            foreach (var club in seededPots[index])
            {
                var card = BuildClubCard(club);
                _cards[club.Id] = card;
                grid.Children.Add(card);
            }
            potStack.Children.Add(grid);
            pots.Children.Add(potStack);
        }
        stack.Children.Add(pots);
        stack.Children.Add(SelectionFooter());

        var content = new Border
        {
            Padding = new Thickness(36, 26),
            Child = stack,
            MaxWidth = 1100,
            HorizontalAlignment = HorizontalAlignment.Center
        };

        return new ScrollViewer
        {
            Content = content,
            HorizontalScrollBarVisibility = Avalonia.Controls.Primitives.ScrollBarVisibility.Disabled,
            VerticalScrollBarVisibility = Avalonia.Controls.Primitives.ScrollBarVisibility.Auto
        };
    }

    private Control Hero()
    {
        var stack = new StackPanel { Spacing = 14, HorizontalAlignment = HorizontalAlignment.Center };

        var badge = new Border
        {
            Width = 82,
            Height = 82,
            CornerRadius = new CornerRadius(41),
            Background = new LinearGradientBrush
            {
                StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
                EndPoint = new RelativePoint(1, 1, RelativeUnit.Relative),
                GradientStops =
                {
                    new GradientStop(Palette.Green, 0),
                    new GradientStop(Palette.Teal, 1)
                }
            },
            Child = Ui.Text("⚽", 34, color: Ui.Brush(Colors.White)),
            HorizontalAlignment = HorizontalAlignment.Center
        };
        stack.Children.Add(badge);

        var titles = new StackPanel { Spacing = 6, HorizontalAlignment = HorizontalAlignment.Center };
        titles.Children.Add(new TextBlock
        {
            Text = "STUDYMANAGER FC",
            FontSize = 11,
            FontWeight = FontWeight.Black,
            Foreground = Ui.Brush(Palette.Green),
            HorizontalAlignment = HorizontalAlignment.Center,
            FontFamily = Ui.Family
        });
        titles.Children.Add(new TextBlock
        {
            Text = "Choose your club",
            FontSize = 32,
            FontWeight = FontWeight.Bold,
            FontFamily = Ui.Family,
            HorizontalAlignment = HorizontalAlignment.Center
        });
        var subtitle = Ui.Secondary(
            "Take charge of one of Europe's 36 elite sides. Study to unlock matchdays, open packs, and build a squad capable of lifting the Champions League.",
            12,
            TextWrapping.Wrap);
        subtitle.TextAlignment = TextAlignment.Center;
        subtitle.MaxWidth = 620;
        subtitle.HorizontalAlignment = HorizontalAlignment.Center;
        titles.Children.Add(subtitle);
        stack.Children.Add(titles);
        return stack;
    }

    private Border BuildClubCard(Club club)
    {
        var inner = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*,Auto") };
        inner.Children.Add(new ClubBadgeControl(club, 40));

        var text = new StackPanel { Spacing = 2, VerticalAlignment = VerticalAlignment.Center };
        text.Children.Add(Ui.Text(club.Name, 12, FontWeight.SemiBold));
        text.Children.Add(Ui.Secondary($"{club.Country} · Pot {ClubDatabaseExtensions.PotNumber(club.Id)}", 9));
        Grid.SetColumn(text, 1);
        text.Margin = new Thickness(10, 0, 8, 0);
        inner.Children.Add(text);

        var rating = new StackPanel { Spacing = 0, VerticalAlignment = VerticalAlignment.Center };
        rating.Children.Add(Ui.Text($"{club.Rating}", 17, FontWeight.Black));
        rating.Children.Add(Ui.Secondary("OVR", 7));
        Grid.SetColumn(rating, 2);
        inner.Children.Add(rating);

        var card = new Border
        {
            Child = inner,
            Padding = new Thickness(12),
            Margin = new Thickness(0, 0, 10, 10),
            Width = 262,
            CornerRadius = new CornerRadius(14),
            Background = Ui.Brush(Color.FromArgb(20, 20, 32, 27)),
            BorderBrush = Ui.Brush(Palette.Hairline),
            BorderThickness = new Thickness(1.4),
            Cursor = new Cursor(StandardCursorType.Hand)
        };
        card.PointerPressed += (_, args) =>
        {
            if (args.GetCurrentPoint(card).Properties.IsLeftButtonPressed) SelectClub(club.Id);
        };
        card.PointerEntered += (_, _) =>
        {
            if (_selectedClubId != club.Id) card.Background = Ui.Brush(Color.FromArgb(38, 20, 32, 27));
        };
        card.PointerExited += (_, _) => RefreshCardStyles();
        return card;
    }

    private void SelectClub(string clubId)
    {
        _selectedClubId = clubId;
        RefreshCardStyles();
        _selectionName.Text = ClubDatabase.Club(clubId)?.Name ?? "No club selected";
        _startButton.SetEnabledState(true);
    }

    private void RefreshCardStyles()
    {
        foreach (var (clubId, card) in _cards)
        {
            var selected = clubId == _selectedClubId;
            card.BorderBrush = Ui.Brush(selected ? Palette.Green : Palette.Hairline);
            card.BorderThickness = new Thickness(selected ? 2 : 1.4);
            card.Background = Ui.Brush(selected
                ? Color.FromArgb(30, Palette.Green.R, Palette.Green.G, Palette.Green.B)
                : Color.FromArgb(20, 20, 32, 27));
        }
    }

    private Control SelectionFooter()
    {
        _selectionName = Ui.Text("No club selected", 17, FontWeight.Bold);
        _error = Ui.Text("", 11, color: Ui.Brush(Palette.Red), wrapping: TextWrapping.Wrap);
        _error.IsVisible = false;

        var text = new StackPanel { Spacing = 4 };
        text.Children.Add(_selectionName);
        var note = Ui.Secondary(
            "You begin with an academy squad and 600 Club Cash. Your first 90 minutes of study unlocks Matchday 1.",
            11,
            TextWrapping.Wrap);
        note.MaxWidth = 520;
        text.Children.Add(note);
        text.Children.Add(_error);

        _startButton = new ActionButton(
            "Start Career  →",
            Palette.Green,
            Colors.White,
            radius: 10,
            padding: new Thickness(20, 10),
            fontSize: 13);
        _startButton.SetEnabledState(false);
        _startButton.VerticalAlignment = VerticalAlignment.Center;
        _startButton.Clicked += StartCareer;

        var row = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        row.Children.Add(text);
        Grid.SetColumn(_startButton, 1);
        row.Children.Add(_startButton);

        return Ui.Card(row, 18, 20);
    }

    private void StartCareer()
    {
        if (_selectedClubId is null) return;
        try
        {
            _store.StartCareer(_selectedClubId);
        }
        catch (Exception exception)
        {
            _error.Text = exception.Message;
            _error.IsVisible = true;
        }
    }
}
