using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using StudyManagerFC.Core;

namespace StudyManagerFC.Desktop;

public static class Palette
{
    public static readonly Color Green = Color.Parse("#2FBF71");
    public static readonly Color Teal = Color.Parse("#1FA8A0");
    public static readonly Color Gold = Color.Parse("#E6B84A");
    public static readonly Color Ink = Color.Parse("#14201B");
    public static readonly Color Secondary = Color.Parse("#66756F");
    public static readonly Color Tertiary = Color.Parse("#8A9993");
    public static readonly Color Orange = Color.Parse("#E08A34");
    public static readonly Color Red = Color.Parse("#CB4B45");
    public static readonly Color Blue = Color.Parse("#4C7FD8");
    public static readonly Color Purple = Color.Parse("#8A6BC4");
    public static readonly Color CardFill = Color.FromArgb(214, 255, 255, 255);
    public static readonly Color Hairline = Color.FromArgb(30, 20, 32, 27);
    public static readonly Color SurfaceTint = Color.FromArgb(20, 20, 32, 27);
}

public static class Ui
{
    public static readonly FontFamily Family = FontFamily.Parse("Segoe UI, SF Pro Text, Helvetica Neue, Arial");

    public static IBrush Brush(Color color) => new SolidColorBrush(color);

    public static IBrush Brush(string hex) => new SolidColorBrush(Color.Parse("#" + hex.TrimStart('#')));

    public static Color Blend(Color color, Color towards, double amount)
    {
        byte Mix(byte a, byte b) => (byte)Math.Round(a + (b - a) * amount);
        return Color.FromArgb(color.A, Mix(color.R, towards.R), Mix(color.G, towards.G), Mix(color.B, towards.B));
    }

    public static Color Hover(Color color) => Blend(color, Colors.White, 0.16);

    public static Color Pressed(Color color) => Blend(color, Colors.Black, 0.1);

    public static TextBlock Text(
        string text,
        double size = 13,
        FontWeight? weight = null,
        IBrush? color = null,
        TextWrapping wrapping = TextWrapping.NoWrap)
    {
        return new TextBlock
        {
            Text = text,
            FontSize = size,
            FontFamily = Family,
            FontWeight = weight ?? FontWeight.Normal,
            Foreground = color ?? Brush(Palette.Ink),
            TextWrapping = wrapping,
            VerticalAlignment = VerticalAlignment.Center
        };
    }

    public static TextBlock Secondary(string text, double size = 10, TextWrapping wrapping = TextWrapping.NoWrap)
        => Text(text, size, color: Brush(Palette.Secondary), wrapping: wrapping);

    public static TextBlock Eyebrow(string text, Color? tint = null)
        => Text(text.ToUpperInvariant(), 10, FontWeight.Bold, Brush(tint ?? Palette.Green));

    public static Border Card(Control content, double padding = 20, double radius = 20, Color? fill = null, Color? border = null)
    {
        return new Border
        {
            Child = content,
            Padding = new Thickness(padding),
            CornerRadius = new CornerRadius(radius),
            Background = Brush(fill ?? Palette.CardFill),
            BorderBrush = Brush(border ?? Palette.Hairline),
            BorderThickness = new Thickness(1)
        };
    }

    public static Border Hairline()
    {
        return new Border
        {
            Height = 1,
            Background = Brush(Palette.Hairline),
            HorizontalAlignment = HorizontalAlignment.Stretch,
            Margin = new Thickness(0, 8)
        };
    }

    public static Control ScreenHeader(string eyebrow, string title, string subtitle)
    {
        var stack = new StackPanel { Spacing = 5 };
        stack.Children.Add(Eyebrow(eyebrow));
        stack.Children.Add(Text(title, 30, FontWeight.Bold));
        stack.Children.Add(Secondary(subtitle, 12, TextWrapping.Wrap));
        return stack;
    }

    public static Control SectionHeader(string title, string? subtitle = null, Color? dot = null)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        var marker = new Border
        {
            Width = 8,
            Height = 8,
            CornerRadius = new CornerRadius(4),
            Background = Brush(dot ?? Palette.Green),
            VerticalAlignment = VerticalAlignment.Center
        };
        row.Children.Add(marker);
        var text = new StackPanel { Spacing = 2 };
        text.Children.Add(Text(title, 16, FontWeight.SemiBold));
        if (subtitle is not null) text.Children.Add(Secondary(subtitle, 10));
        row.Children.Add(text);
        return row;
    }

    public static Border Pill(string text, Color tint, string? icon = null)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
        if (!string.IsNullOrEmpty(icon)) row.Children.Add(Text(icon!, 9, FontWeight.Bold, Brush(tint)));
        row.Children.Add(Text(text, 10, FontWeight.SemiBold, Brush(tint)));
        return new Border
        {
            Child = row,
            Padding = new Thickness(8, 4),
            CornerRadius = new CornerRadius(999),
            Background = Brush(Color.FromArgb(31, tint.R, tint.G, tint.B)),
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Center
        };
    }

    public static Border MetricTile(string title, string value, string? subtitle, string icon, Color tint)
    {
        var stack = new StackPanel { Spacing = 10 };
        var top = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
        top.Children.Add(new Border
        {
            Width = 26,
            Height = 26,
            CornerRadius = new CornerRadius(13),
            Background = Brush(Color.FromArgb(30, tint.R, tint.G, tint.B)),
            Child = Text(icon, 12, color: Brush(tint))
        });
        stack.Children.Add(top);
        stack.Children.Add(Text(value, 22, FontWeight.Bold));
        var labels = new StackPanel { Spacing = 1 };
        labels.Children.Add(Text(title, 11, FontWeight.SemiBold));
        if (subtitle is not null) labels.Children.Add(Secondary(subtitle, 9));
        stack.Children.Add(labels);
        return Card(stack, 14, 16);
    }

    public static Border IconCircle(string icon, Color tint, double size = 30, double fontSize = 12)
    {
        return new Border
        {
            Width = size,
            Height = size,
            CornerRadius = new CornerRadius(size / 2),
            Background = Brush(Color.FromArgb(31, tint.R, tint.G, tint.B)),
            Child = Text(icon, fontSize, color: Brush(tint)),
            VerticalAlignment = VerticalAlignment.Center
        };
    }

    public static Color RarityColor(PlayerRarity rarity) => rarity switch
    {
        PlayerRarity.Bronze => Color.Parse("#B47142"),
        PlayerRarity.Silver => Color.Parse("#AAB5C2"),
        PlayerRarity.Gold => Color.Parse("#E0B94E"),
        PlayerRarity.Wonderkid => Color.Parse("#42D6C3"),
        _ => Color.Parse("#E7D28A")
    };

    public static Color[] RarityGradient(PlayerRarity rarity) => rarity switch
    {
        PlayerRarity.Bronze => [Color.Parse("#5D3720"), Color.Parse("#B47142")],
        PlayerRarity.Silver => [Color.Parse("#3E4854"), Color.Parse("#AAB5C2")],
        PlayerRarity.Gold => [Color.Parse("#4E3B13"), Color.Parse("#C39A2A")],
        PlayerRarity.Wonderkid => [Color.Parse("#123C3A"), Color.Parse("#1B8C86"), Color.Parse("#54D7C4")],
        _ => [Color.Parse("#121A2B"), Color.Parse("#5A4A20"), Color.Parse("#DCC477")]
    };

    public static bool IsLightBadge(string hex)
    {
        var color = Color.Parse("#" + hex.TrimStart('#'));
        var luminance = (0.299 * color.R + 0.587 * color.G + 0.114 * color.B) / 255;
        return luminance > 0.62;
    }
}

/// <summary>
/// A clickable bordered surface. Using our own control keeps the macOS look instead of
/// inheriting the platform button chrome and its hover colours.
/// </summary>
public class ActionButton : Border
{
    private Color _background;
    private Color _hover;
    private readonly Color _borderColor;
    private readonly double _borderThickness;
    private readonly TextBlock _label;
    private bool _hovered;

    public event Action? Clicked;

    public ActionButton(
        string text,
        Color? background = null,
        Color? foreground = null,
        Color? border = null,
        double borderThickness = 1,
        double radius = 10,
        Thickness? padding = null,
        double fontSize = 12,
        FontWeight? weight = null,
        HorizontalAlignment align = HorizontalAlignment.Left,
        double? minWidth = null,
        double? width = null)
    {
        _background = background ?? Colors.Transparent;
        _hover = Ui.Hover(_background == Colors.Transparent ? Color.FromArgb(16, 20, 32, 27) : _background);
        _borderColor = border ?? Colors.Transparent;
        _borderThickness = border is null ? 0 : borderThickness;
        _label = Ui.Text(text, fontSize, weight ?? FontWeight.SemiBold, Ui.Brush(foreground ?? Palette.Ink));
        _label.HorizontalAlignment = HorizontalAlignment.Center;
        _label.TextAlignment = TextAlignment.Center;
        Child = _label;
        Padding = padding ?? new Thickness(14, 8);
        CornerRadius = new CornerRadius(radius);
        Background = Ui.Brush(_background);
        BorderBrush = Ui.Brush(_borderColor);
        BorderThickness = new Thickness(_borderThickness);
        HorizontalAlignment = align;
        if (minWidth.HasValue) MinWidth = minWidth.Value;
        if (width.HasValue) Width = width.Value;
        Cursor = new Cursor(StandardCursorType.Hand);
        Focusable = true;
        PointerEntered += (_, _) =>
        {
            _hovered = true;
            if (IsEnabled) Background = Ui.Brush(_hover);
        };
        PointerExited += (_, _) =>
        {
            _hovered = false;
            Background = Ui.Brush(_background);
        };
        PointerPressed += (_, args) =>
        {
            if (!IsEnabled) return;
            if (args.GetCurrentPoint(this).Properties.IsLeftButtonPressed) Click();
        };
        KeyDown += (_, args) =>
        {
            if (!IsEnabled) return;
            if (args.Key is Key.Enter or Key.Space)
            {
                Click();
                args.Handled = true;
            }
        };
    }

    public string Text
    {
        get => _label.Text ?? "";
        set => _label.Text = value;
    }

    public void SetEnabledState(bool enabled)
    {
        IsEnabled = enabled;
        Opacity = enabled ? 1 : 0.45;
        Cursor = enabled ? new Cursor(StandardCursorType.Hand) : new Cursor(StandardCursorType.Arrow);
    }

    public void SetColors(Color background, Color foreground)
    {
        _background = background;
        _hover = background == Colors.Transparent ? Color.FromArgb(16, 20, 32, 27) : Ui.Hover(background);
        Background = Ui.Brush(_hovered ? _hover : background);
        _label.Foreground = Ui.Brush(foreground);
    }

    private void Click()
    {
        Background = Ui.Brush(Ui.Pressed(_background));
        Clicked?.Invoke();
    }
}

public class SegmentedControl : Border
{
    private readonly List<(string Label, ActionButton Button)> _options = [];
    private int _selectedIndex;

    public event Action<int>? SelectionChanged;

    public SegmentedControl(IEnumerable<string> labels, int selectedIndex = 0, double width = 280)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
        foreach (var label in labels)
        {
            var index = _options.Count;
            var button = new ActionButton(label, radius: 8, padding: new Thickness(16, 6), fontSize: 11);
            button.Clicked += () => Select(index, true);
            _options.Add((label, button));
            row.Children.Add(button);
        }
        Child = row;
        Padding = new Thickness(4);
        CornerRadius = new CornerRadius(10);
        Background = Ui.Brush(Color.FromArgb(18, 20, 32, 27));
        HorizontalAlignment = HorizontalAlignment.Left;
        Width = width;
        _selectedIndex = selectedIndex;
        ApplySelection();
    }

    public int SelectedIndex => _selectedIndex;

    public void Select(int index, bool notify)
    {
        if (index < 0 || index >= _options.Count) return;
        _selectedIndex = index;
        ApplySelection();
        if (notify) SelectionChanged?.Invoke(index);
    }

    private void ApplySelection()
    {
        for (var index = 0; index < _options.Count; index++)
        {
            var selected = index == _selectedIndex;
            var (_, button) = _options[index];
            button.Background = Ui.Brush(selected ? Palette.Green : Colors.Transparent);
            button.SetColors(selected ? Palette.Green : Colors.Transparent, selected ? Colors.White : Palette.Secondary);
        }
    }
}

public class Stepper : Border
{
    private readonly TextBlock _valueLabel;
    private int _value;

    public int Minimum { get; set; }
    public int Maximum { get; set; } = 100;
    public int Step { get; set; } = 1;
    public string Suffix { get; set; } = "";

    public event Action<int>? ValueChanged;

    public Stepper(int value, string prefix = "", int minimum = 0, int maximum = 100, int step = 1, string suffix = "")
    {
        Minimum = minimum;
        Maximum = maximum;
        Step = step;
        Suffix = suffix;
        _value = Math.Clamp(value, minimum, maximum);
        _valueLabel = Ui.Text(Format(prefix), 11, FontWeight.SemiBold);
        _valueLabel.MinWidth = 78;

        var minus = new ActionButton("−", Color.FromArgb(16, 20, 32, 27), Palette.Ink, radius: 7, padding: new Thickness(9, 2), fontSize: 13);
        var plus = new ActionButton("+", Color.FromArgb(16, 20, 32, 27), Palette.Ink, radius: 7, padding: new Thickness(9, 2), fontSize: 13);
        minus.Clicked += () => Adjust(-Step);
        plus.Clicked += () => Adjust(Step);

        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6, VerticalAlignment = VerticalAlignment.Center };
        row.Children.Add(minus);
        row.Children.Add(_valueLabel);
        row.Children.Add(plus);
        Child = row;
        Padding = new Thickness(4, 3);
        CornerRadius = new CornerRadius(9);
        Background = Ui.Brush(Color.FromArgb(14, 20, 32, 27));
        HorizontalAlignment = HorizontalAlignment.Left;
        _prefix = prefix;
    }

    private readonly string _prefix;

    public int Value
    {
        get => _value;
        set
        {
            _value = Math.Clamp(value, Minimum, Maximum);
            _valueLabel.Text = Format(_prefix);
        }
    }

    public void Reset(int value)
    {
        Value = value;
    }

    private void Adjust(int delta)
    {
        Value = _value + delta;
        ValueChanged?.Invoke(_value);
    }

    private string Format(string prefix)
        => string.IsNullOrEmpty(prefix) ? $"{_value}{Suffix}" : $"{_value} {prefix}";
}

public class ClubBadgeControl : Border
{
    public ClubBadgeControl(Club club, double size = 42)
    {
        Width = size;
        Height = size;
        CornerRadius = new CornerRadius(size / 2);
        Background = Ui.Brush(Color.Parse("#" + club.PrimaryHex.TrimStart('#')));
        BorderBrush = Ui.Brush(Color.Parse("#" + club.SecondaryHex.TrimStart('#')));
        BorderThickness = new Thickness(Math.Max(2, size * 0.055));
        Child = new TextBlock
        {
            Text = club.Code,
            FontSize = size * 0.25,
            FontWeight = FontWeight.Bold,
            FontFamily = Ui.Family,
            Foreground = Ui.Brush(Ui.IsLightBadge(club.PrimaryHex) ? Color.FromArgb(210, 0, 0, 0) : Colors.White),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            TextAlignment = TextAlignment.Center
        };
        VerticalAlignment = VerticalAlignment.Center;
        HorizontalAlignment = HorizontalAlignment.Left;
    }
}

public class PlayerCardView : Border
{
    public PlayerCardView(Player player, double width = 178)
    {
        var height = width * 1.39;
        Width = width;
        Height = height;
        CornerRadius = new CornerRadius(width * 0.09);
        var gradient = Ui.RarityGradient(player.Rarity);
        var stops = new GradientStops();
        for (var index = 0; index < gradient.Length; index++)
        {
            stops.Add(new GradientStop(gradient[index], index / (double)Math.Max(1, gradient.Length - 1)));
        }
        Background = new LinearGradientBrush
        {
            StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
            EndPoint = new RelativePoint(1, 1, RelativeUnit.Relative),
            GradientStops = stops
        };
        BorderBrush = Ui.Brush(Color.FromArgb(66, 255, 255, 255));
        BorderThickness = new Thickness(1);
        ClipToBounds = true;

        var foreground = player.Rarity == PlayerRarity.Silver ? Color.Parse("#14201B") : Colors.White;
        var secondary = player.Rarity == PlayerRarity.Silver ? Color.FromArgb(158, 0, 0, 0) : Color.FromArgb(184, 255, 255, 255);

        var content = new Grid { RowDefinitions = new RowDefinitions("Auto,*,Auto") };

        var top = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        var rating = new StackPanel { Spacing = -4 };
        rating.Children.Add(Ui.Text($"{player.Overall}", width * 0.22, FontWeight.Black, Ui.Brush(foreground)));
        rating.Children.Add(Ui.Text(player.Position.Abbreviation(), width * 0.067, FontWeight.Bold, Ui.Brush(secondary)));
        top.Children.Add(rating);

        var right = new StackPanel { Spacing = 5, HorizontalAlignment = HorizontalAlignment.Right };
        right.Children.Add(Ui.Text(player.Nation.Flag, width * 0.095));
        right.Children.Add(new Border
        {
            Background = Ui.Brush(Color.FromArgb((byte)(player.Rarity == PlayerRarity.Silver ? 30 : 56), 0, 0, 0)),
            CornerRadius = new CornerRadius(999),
            Padding = new Thickness(6, 3),
            Child = Ui.Text(player.Rarity.DisplayName().ToUpperInvariant(), 8, FontWeight.Bold,
                Ui.Brush(player.Rarity == PlayerRarity.Silver ? Color.FromArgb(190, 0, 0, 0) : Color.FromArgb(235, 255, 255, 255)))
        });
        Grid.SetColumn(right, 1);
        top.Children.Add(right);
        content.Children.Add(top);

        var bottom = new StackPanel { Spacing = 5, VerticalAlignment = VerticalAlignment.Bottom };
        bottom.Children.Add(Ui.Text(player.Name, width * 0.082, FontWeight.Bold, Ui.Brush(foreground)));
        var meta = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 7 };
        meta.Children.Add(Ui.Text(player.NationCode, width * 0.052, FontWeight.SemiBold, Ui.Brush(secondary)));
        meta.Children.Add(Ui.Text($"AGE {player.Age}", width * 0.052, FontWeight.SemiBold, Ui.Brush(secondary)));
        meta.Children.Add(Ui.Text($"POT {player.Potential}", width * 0.052, FontWeight.SemiBold, Ui.Brush(secondary)));
        bottom.Children.Add(meta);

        var attributes = new UniformGrid { Columns = 5, Margin = new Thickness(0, 4, 0, 0) };
        attributes.Children.Add(AttributeCell("PAC", player.Attributes.Pace, foreground, width));
        attributes.Children.Add(AttributeCell("SHO", player.Attributes.Shooting, foreground, width));
        attributes.Children.Add(AttributeCell("PAS", player.Attributes.Passing, foreground, width));
        attributes.Children.Add(AttributeCell("DEF", player.Attributes.Defending, foreground, width));
        attributes.Children.Add(AttributeCell("PHY", player.Attributes.Physical, foreground, width));
        bottom.Children.Add(attributes);
        Grid.SetRow(bottom, 2);
        content.Children.Add(bottom);

        Child = new Border
        {
            Padding = new Thickness(width * 0.085),
            Child = content
        };
    }

    private static Control AttributeCell(string label, int value, Color foreground, double width)
    {
        var stack = new StackPanel { Spacing = 1, HorizontalAlignment = HorizontalAlignment.Center };
        stack.Children.Add(Ui.Text($"{value}", width * 0.052, FontWeight.Bold, Ui.Brush(foreground)));
        stack.Children.Add(Ui.Text(label, width * 0.037, FontWeight.SemiBold, Ui.Brush(Color.FromArgb(170, foreground.R, foreground.G, foreground.B))));
        return stack;
    }
}

public class ReadinessBar : Border
{
    private readonly Border _fill;
    private double _progress;

    public ReadinessBar(double height = 10, Color? tint = null)
    {
        Height = height;
        CornerRadius = new CornerRadius(height / 2);
        Background = Ui.Brush(Color.FromArgb(18, 20, 32, 27));
        ClipToBounds = true;
        var color = tint ?? Palette.Green;
        _fill = new Border
        {
            Width = 0,
            HorizontalAlignment = HorizontalAlignment.Left,
            CornerRadius = new CornerRadius(height / 2),
            Background = new LinearGradientBrush
            {
                StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
                EndPoint = new RelativePoint(1, 0, RelativeUnit.Relative),
                GradientStops =
                {
                    new GradientStop(Color.FromArgb(190, color.R, color.G, color.B), 0),
                    new GradientStop(color, 1)
                }
            }
        };
        Child = _fill;
        SizeChanged += (_, _) => Apply();
    }

    public double Progress
    {
        get => _progress;
        set
        {
            _progress = Math.Clamp(value, 0, 1);
            Apply();
        }
    }

    private void Apply()
    {
        _fill.Width = Math.Max(0, Bounds.Width * _progress);
    }
}

public class ChemistryRing : Control
{
    private int _chemistry;

    public ChemistryRing(int chemistry, double size = 64)
    {
        _chemistry = chemistry;
        Width = size;
        Height = size;
    }

    public void SetChemistry(int chemistry)
    {
        _chemistry = chemistry;
        InvalidateVisual();
    }

    public override void Render(DrawingContext context)
    {
        var size = Math.Min(Bounds.Width, Bounds.Height);
        if (size <= 0) return;
        var center = new Point(Bounds.Width / 2, Bounds.Height / 2);
        var radius = size / 2 - 6;
        var trackPen = new Pen(new SolidColorBrush(Color.FromArgb(24, 20, 32, 27)), 7);
        context.DrawEllipse(null, trackPen, center, radius, radius);

        var progress = Math.Clamp(_chemistry / 100.0, 0, 1);
        if (progress > 0.001)
        {
            var geometry = new StreamGeometry();
            using (var sink = geometry.Open())
            {
                var startAngle = -Math.PI / 2;
                var sweep = progress * Math.PI * 2;
                var steps = Math.Max(2, (int)(progress * 96));
                for (var index = 0; index <= steps; index++)
                {
                    var angle = startAngle + sweep * index / steps;
                    var point = new Point(center.X + radius * Math.Cos(angle), center.Y + radius * Math.Sin(angle));
                    if (index == 0) sink.BeginFigure(point, false);
                    else sink.LineTo(point);
                }
                sink.EndFigure(false);
            }
            var pen = new Pen(
                new LinearGradientBrush
                {
                    StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
                    EndPoint = new RelativePoint(0, 1, RelativeUnit.Relative),
                    GradientStops =
                    {
                        new GradientStop(Palette.Green, 0),
                        new GradientStop(Palette.Teal, 1)
                    }
                },
                7,
                null,
                PenLineCap.Round);
            context.DrawGeometry(null, pen, geometry);
        }

        DrawCentredText(context, $"{_chemistry}", 17, FontWeight.Bold, Palette.Ink, center.Y - 7);
        DrawCentredText(context, "CHEM", 7, FontWeight.Bold, Palette.Secondary, center.Y + 10);
    }

    private void DrawCentredText(DrawingContext context, string text, double size, FontWeight weight, Color color, double y)
    {
        var formatted = new FormattedText(
            text,
            System.Globalization.CultureInfo.CurrentCulture,
            FlowDirection.LeftToRight,
            new Typeface(Ui.Family, FontStyle.Normal, weight),
            size,
            Ui.Brush(color));
        context.DrawText(formatted, new Point(Bounds.Width / 2 - formatted.Width / 2, y - formatted.Height / 2));
    }
}

public class PitchMarkings : Control
{
    public override void Render(DrawingContext context)
    {
        var width = Bounds.Width;
        var height = Bounds.Height;
        if (width < 40 || height < 40) return;
        var line = new Pen(new SolidColorBrush(Color.FromArgb(84, 255, 255, 255)), 1.2);
        const double inset = 18;
        var field = new Rect(inset, inset, width - inset * 2, height - inset * 2);

        context.DrawRectangle(null, line, field, 5, 5);
        context.DrawLine(line, new Point(field.X, field.Center.Y), new Point(field.Right, field.Center.Y));
        context.DrawEllipse(null, line, new Point(field.Center.X, field.Center.Y), 42, 42);
        context.DrawEllipse(new SolidColorBrush(Color.FromArgb(84, 255, 255, 255)), null,
            new Point(field.Center.X, field.Center.Y), 2.5, 2.5);

        var boxWidth = field.Width * 0.46;
        var boxHeight = field.Height * 0.15;
        context.DrawRectangle(null, line, new Rect(field.Center.X - boxWidth / 2, field.Y, boxWidth, boxHeight));
        context.DrawRectangle(null, line, new Rect(field.Center.X - boxWidth / 2, field.Bottom - boxHeight, boxWidth, boxHeight));

        var sixWidth = field.Width * 0.23;
        var sixHeight = field.Height * 0.06;
        context.DrawRectangle(null, line, new Rect(field.Center.X - sixWidth / 2, field.Y, sixWidth, sixHeight));
        context.DrawRectangle(null, line, new Rect(field.Center.X - sixWidth / 2, field.Bottom - sixHeight, sixWidth, sixHeight));
    }
}

public class MiniPlayerCardControl : Border
{
    private readonly StackPanel _stack = new()
    {
        Spacing = 3,
        VerticalAlignment = VerticalAlignment.Center,
        HorizontalAlignment = HorizontalAlignment.Center
    };

    public event Action? Clicked;

    public MiniPlayerCardControl(Player? player, string positionLabel)
    {
        Width = 82;
        Height = 94;
        CornerRadius = new CornerRadius(11);
        BorderThickness = new Thickness(1);
        Child = _stack;
        Cursor = new Cursor(StandardCursorType.Hand);
        PointerPressed += (_, args) =>
        {
            if (args.GetCurrentPoint(this).Properties.IsLeftButtonPressed) Clicked?.Invoke();
        };
        SetPlayer(player, positionLabel);
    }

    public void SetPlayer(Player? player, string positionLabel)
    {
        _stack.Children.Clear();
        Background = Ui.Brush(Color.FromArgb((byte)(player is null ? 38 : 71), 0, 0, 0));
        BorderBrush = Ui.Brush(Color.FromArgb((byte)(player is null ? 41 : 59), 255, 255, 255));

        if (player is null)
        {
            _stack.Children.Add(new Border
            {
                Width = 43,
                Height = 43,
                CornerRadius = new CornerRadius(22),
                BorderBrush = Ui.Brush(Color.FromArgb(133, 255, 255, 255)),
                BorderThickness = new Thickness(1.4),
                Child = Ui.Text("+", 16, FontWeight.SemiBold, Ui.Brush(Color.FromArgb(190, 255, 255, 255)))
            });
            _stack.Children.Add(Ui.Text(positionLabel, 10, FontWeight.Bold, Ui.Brush(Color.FromArgb(204, 255, 255, 255))));
            _stack.Children.Add(Ui.Text("Empty", 8, FontWeight.Medium, Ui.Brush(Color.FromArgb(128, 255, 255, 255))));
            return;
        }

        var accent = Ui.RarityColor(player.Rarity);
        _stack.Children.Add(new Border
        {
            Width = 43,
            Height = 43,
            CornerRadius = new CornerRadius(22),
            Background = Ui.Brush(Color.FromArgb(61, accent.R, accent.G, accent.B)),
            BorderBrush = Ui.Brush(Color.FromArgb(204, accent.R, accent.G, accent.B)),
            BorderThickness = new Thickness(1.5),
            Child = Ui.Text($"{player.Overall}", 17, FontWeight.Black, Ui.Brush(Colors.White))
        });
        _stack.Children.Add(Ui.Text(player.Surname, 10, FontWeight.SemiBold, Ui.Brush(Colors.White)));
        _stack.Children.Add(Ui.Text($"POT {player.Potential}", 7, FontWeight.Bold, Ui.Brush(accent)));
        _stack.Children.Add(Ui.Text(positionLabel, 8, FontWeight.Bold, Ui.Brush(Color.FromArgb(170, 255, 255, 255))));
    }
}

public class PitchView : Panel
{
    private readonly Border _turf;
    private readonly PitchMarkings _markings;
    private readonly List<(LineupSlot Slot, MiniPlayerCardControl Node)> _nodes = [];

    public event Action<LineupSlot>? SlotSelected;

    public PitchView()
    {
        Width = 560;
        Height = 718;
        _turf = new Border
        {
            CornerRadius = new CornerRadius(20),
            Background = new LinearGradientBrush
            {
                StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
                EndPoint = new RelativePoint(0, 1, RelativeUnit.Relative),
                GradientStops =
                {
                    new GradientStop(Color.Parse("#2B7A4D"), 0),
                    new GradientStop(Color.Parse("#195534"), 1)
                }
            }
        };
        _markings = new PitchMarkings { IsHitTestVisible = false };
        Children.Add(_turf);
        Children.Add(_markings);

        foreach (var slot in LineupSlot.All)
        {
            var node = new MiniPlayerCardControl(null, slot.Label);
            var captured = slot;
            node.Clicked += () => SlotSelected?.Invoke(captured);
            _nodes.Add((slot, node));
            Children.Add(node);
        }
    }

    public void Update(Dictionary<string, Player> lineup)
    {
        foreach (var (slot, node) in _nodes)
        {
            lineup.TryGetValue(slot.Id, out var player);
            node.SetPlayer(player, slot.Label);
        }
    }

    protected override Size MeasureOverride(Size availableSize)
    {
        _turf.Measure(new Size(Width, Height));
        _markings.Measure(new Size(Width, Height));
        foreach (var (_, node) in _nodes) node.Measure(new Size(82, 94));
        return new Size(Width, Height);
    }

    protected override Size ArrangeOverride(Size finalSize)
    {
        _turf.Arrange(new Rect(finalSize));
        _markings.Arrange(new Rect(finalSize));
        foreach (var (slot, node) in _nodes)
        {
            node.Arrange(new Rect(slot.X * finalSize.Width - 41, slot.Y * finalSize.Height - 47, 82, 94));
        }
        return finalSize;
    }
}
