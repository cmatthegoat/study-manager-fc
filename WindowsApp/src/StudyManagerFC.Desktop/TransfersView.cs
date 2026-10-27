using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Templates;
using Avalonia.VisualTree;
using Avalonia.Layout;
using Avalonia.Media;
using StudyManagerFC.Core;

namespace StudyManagerFC.Desktop;

public class TransfersView : IPage
{
    private readonly GameStore _store;
    private readonly MainWindow _window;

    private ListBox _list = null!;
    private TextBox _search = null!;
    private ComboBox _clubFilter = null!;
    private ComboBox _positionFilter = null!;
    private ActionButton _sortToggle = null!;
    private TextBlock _countLabel = null!;
    private TextBlock _cashLabel = null!;
    private TextBlock _status = null!;
    private bool _sortByRating = true;
    private string _signature = "";
    private List<Club> _clubs = [];

    public Control View { get; }

    public TransfersView(GameStore store, MainWindow window)
    {
        _store = store;
        _window = window;
        View = Build();
        Refresh();
    }

    private Control Build()
    {
        var page = new Grid
        {
            RowDefinitions = new RowDefinitions("Auto,Auto,Auto,*"),
            Margin = new Thickness(28)
        };

        page.Children.Add(BuildHeader());

        var filters = BuildFilters();
        Grid.SetRow(filters, 1);
        page.Children.Add(filters);

        _status = Ui.Text("", 11, color: Ui.Brush(Palette.Orange), wrapping: TextWrapping.Wrap);
        _status.Margin = new Thickness(0, 8, 0, 0);
        _status.IsVisible = false;
        Grid.SetRow(_status, 2);
        page.Children.Add(_status);

        _list = new ListBox
        {
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            Padding = new Thickness(0),
            Margin = new Thickness(0, 10, 0, 0),
            ItemTemplate = new FuncDataTemplate<TransferListing>((listing, _) => BuildRow(listing), true)
        };
        var listCard = Ui.Card(_list, 10, 18);
        Grid.SetRow(listCard, 3);
        page.Children.Add(listCard);

        var host = new Border { Child = page, MaxWidth = 1200, HorizontalAlignment = HorizontalAlignment.Center };
        return host;
    }

    private Control BuildHeader()
    {
        var header = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        header.Children.Add(Ui.ScreenHeader(
            "Transfer Market",
            "Sign Players from Other Clubs",
            "Every signing costs Club Cash. The higher a player's overall, the more they cost — elite talent is expensive."));

        var cashStack = new StackPanel { Spacing = 1 };
        cashStack.Children.Add(Ui.Text("CLUB CASH", 8, FontWeight.Black, Ui.Brush(Palette.Secondary)));
        _cashLabel = Ui.Text("", 20, FontWeight.Bold, Ui.Brush(Palette.Gold));
        cashStack.Children.Add(_cashLabel);
        var cashCard = Ui.Card(cashStack, 12, 14);
        cashCard.VerticalAlignment = VerticalAlignment.Top;
        Grid.SetColumn(cashCard, 1);
        cashCard.Margin = new Thickness(16, 0, 0, 0);
        header.Children.Add(cashCard);
        return header;
    }

    private Control BuildFilters()
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        _search = new TextBox { Watermark = "Search players, clubs or positions", Width = 300 };
        _search.TextChanged += (_, _) => ApplyFilters();
        row.Children.Add(_search);

        _clubs = ClubDatabase.All
            .Where(club => club.Id != _store.State.ManagedClubID)
            .OrderBy(club => club.Name, StringComparer.Ordinal)
            .ToList();
        _clubFilter = new ComboBox
        {
            ItemsSource = new[] { "All clubs" }.Concat(_clubs.Select(club => club.ShortName)).ToList(),
            SelectedIndex = 0,
            Width = 160
        };
        _clubFilter.SelectionChanged += (_, _) => ApplyFilters();
        row.Children.Add(_clubFilter);

        _positionFilter = new ComboBox
        {
            ItemsSource = new[] { "All positions" }
                .Concat(PositionGroupExtensionsDisplay.All.Select(group => group.DisplayName()))
                .ToList(),
            SelectedIndex = 0,
            Width = 160
        };
        _positionFilter.SelectionChanged += (_, _) => ApplyFilters();
        row.Children.Add(_positionFilter);

        _sortToggle = new ActionButton("Sort: Rating", Color.FromArgb(20, 20, 32, 27), Palette.Ink,
            radius: 9, padding: new Thickness(12, 6), fontSize: 11);
        _sortToggle.Clicked += () =>
        {
            _sortByRating = !_sortByRating;
            _sortToggle.Text = _sortByRating ? "Sort: Rating" : "Sort: Club";
            ApplyFilters();
        };
        row.Children.Add(_sortToggle);

        _countLabel = Ui.Secondary("", 10);
        _countLabel.VerticalAlignment = VerticalAlignment.Center;
        _countLabel.Margin = new Thickness(10, 0, 0, 0);
        row.Children.Add(_countLabel);

        var card = Ui.Card(row, 12, 14);
        card.Margin = new Thickness(0, 16, 0, 0);
        return card;
    }

    private Control BuildRow(TransferListing? listing)
    {
        // The virtualising list can ask for a template while a container is being recycled.
        if (listing is null) return new Border { Height = 0 };

        var fee = _store.TransferFee(listing);
        var alreadyOwned = _store.State.Players.Any(player =>
            player.Name == listing.Seed.Name && player.Position == listing.Seed.Position);
        var canAfford = _store.State.ClubCash >= fee;

        var row = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*,Auto,Auto,Auto"), Margin = new Thickness(0, 1) };

        row.Children.Add(new Border
        {
            Width = 38,
            Height = 38,
            CornerRadius = new CornerRadius(19),
            Background = Ui.Brush(Color.FromArgb(41, Palette.Green.R, Palette.Green.G, Palette.Green.B)),
            Child = Ui.Text($"{listing.Seed.Rating}", 13, FontWeight.Black)
        });

        var text = new StackPanel { Spacing = 2, Margin = new Thickness(12, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
        var nameRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 7 };
        nameRow.Children.Add(Ui.Text(listing.Seed.Name, 13, FontWeight.SemiBold));
        var potential = Ui.Pill($"POT {_store.ProjectedPotential(listing)}", Palette.Teal);
        nameRow.Children.Add(potential);
        text.Children.Add(nameRow);
        text.Children.Add(Ui.Secondary(
            $"{listing.Seed.Position.DisplayName()} · {Nations.For(listing.Seed.NationCode).Flag} {listing.Seed.NationCode}", 9));
        Grid.SetColumn(text, 1);
        row.Children.Add(text);

        var club = listing.Club;
        if (club is not null)
        {
            var clubRow = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Spacing = 7,
                Width = 150,
                VerticalAlignment = VerticalAlignment.Center
            };
            clubRow.Children.Add(new ClubBadgeControl(club, 24));
            clubRow.Children.Add(Ui.Secondary(club.ShortName, 11));
            Grid.SetColumn(clubRow, 2);
            row.Children.Add(clubRow);
        }

        var feeStack = new StackPanel { Spacing = 1, Width = 92, VerticalAlignment = VerticalAlignment.Center };
        var feeText = Ui.Text(fee.ToString("N0"), 12, FontWeight.Bold,
            Ui.Brush(canAfford || alreadyOwned ? Palette.Gold : Palette.Secondary));
        feeText.TextAlignment = TextAlignment.Right;
        feeStack.Children.Add(feeText);
        var hint = canAfford || alreadyOwned
            ? Ui.Secondary("Club Cash", 8)
            : Ui.Text($"{(fee - _store.State.ClubCash):N0} short", 8, FontWeight.SemiBold, Ui.Brush(Palette.Orange));
        hint.TextAlignment = TextAlignment.Right;
        feeStack.Children.Add(hint);
        Grid.SetColumn(feeStack, 3);
        row.Children.Add(feeStack);

        var actionHost = new ContentControl { Margin = new Thickness(12, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
        if (alreadyOwned)
        {
            actionHost.Content = Ui.Pill("IN SQUAD", Palette.Secondary, "✓");
        }
        else
        {
            var sign = new ActionButton("+  Sign", canAfford ? Palette.Green : Color.FromArgb(30, 20, 32, 27),
                canAfford ? Colors.White : Palette.Secondary, radius: 9, padding: new Thickness(12, 6), fontSize: 11);
            if (!canAfford) sign.SetEnabledState(false);
            var captured = listing;
            sign.Clicked += () =>
            {
                try
                {
                    _store.SignFromTransfer(captured);
                    _status.IsVisible = false;
                }
                catch (Exception exception)
                {
                    _status.Text = exception.Message;
                    _status.IsVisible = true;
                }
            };
            actionHost.Content = sign;
        }
        Grid.SetColumn(actionHost, 4);
        row.Children.Add(actionHost);

        return new Border
        {
            Child = row,
            Padding = new Thickness(10, 8),
            CornerRadius = new CornerRadius(12),
            Background = Ui.Brush(Color.FromArgb(8, 20, 32, 27))
        };
    }

    private void ApplyFilters()
    {
        if (_list is null) return;
        var listings = _store.TransferMarket;
        var query = _search.Text?.Trim() ?? "";
        var clubIndex = Math.Max(0, _clubFilter.SelectedIndex);
        var positionIndex = Math.Max(0, _positionFilter.SelectedIndex);

        IEnumerable<TransferListing> filtered = listings;
        if (clubIndex > 0 && clubIndex - 1 < _clubs.Count)
        {
            var clubId = _clubs[clubIndex - 1].Id;
            filtered = filtered.Where(listing => listing.ClubId == clubId);
        }
        if (positionIndex > 0)
        {
            var group = PositionGroupExtensionsDisplay.All[positionIndex - 1];
            filtered = filtered.Where(listing => listing.Seed.Position.Group() == group);
        }
        if (query.Length > 0)
        {
            filtered = filtered.Where(listing =>
                listing.Seed.Name.Contains(query, StringComparison.OrdinalIgnoreCase)
                || (listing.Club?.Name.Contains(query, StringComparison.OrdinalIgnoreCase) ?? false)
                || listing.Seed.Position.DisplayName().Contains(query, StringComparison.OrdinalIgnoreCase));
        }

        var result = _sortByRating
            ? filtered.OrderByDescending(listing => listing.Seed.Rating)
                .ThenBy(listing => listing.Club?.Name ?? "", StringComparer.Ordinal)
                .ThenBy(listing => listing.Seed.Name, StringComparer.Ordinal)
                .ToList()
            : filtered.OrderBy(listing => listing.Club?.Name ?? "", StringComparer.Ordinal)
                .ThenByDescending(listing => listing.Seed.Rating)
                .ThenBy(listing => listing.Seed.Name, StringComparer.Ordinal)
                .ToList();

        var scroll = _list.GetVisualDescendants().OfType<ScrollViewer>().FirstOrDefault();
        var offset = scroll?.Offset ?? default;
        _list.ItemsSource = result;
        _countLabel.Text = $"{result.Count} players available";
        if (scroll is not null)
        {
            Avalonia.Threading.Dispatcher.UIThread.Post(() => scroll.Offset = offset);
        }
    }

    public void Refresh()
    {
        _cashLabel.Text = _store.State.ClubCash.ToString("N0");
        var signature = $"{_store.State.ClubCash}|{string.Join(",", _store.State.Players.Select(player => player.Id))}";
        if (signature == _signature) return;
        _signature = signature;
        ApplyFilters();
    }
}
