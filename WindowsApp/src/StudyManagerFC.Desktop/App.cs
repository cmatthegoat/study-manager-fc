using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Controls.Primitives;
using Avalonia.Media;
using Avalonia.Styling;
using Avalonia.Themes.Fluent;
using StudyManagerFC.Core;

namespace StudyManagerFC.Desktop;

public class App : Application
{
    public override void Initialize()
    {
        Styles.Add(new FluentTheme());
        RequestedThemeVariant = ThemeVariant.Light;
        Styles.Add(BuildStyles());
    }

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            desktop.MainWindow = new MainWindow(new GameStore());
        }
        base.OnFrameworkInitializationCompleted();
    }

    private static Styles BuildStyles()
    {
        var styles = new Styles();

        styles.Add(new Style(x => x.OfType<Window>())
        {
            Setters =
            {
                new Setter(TemplatedControl.FontFamilyProperty, Ui.Family),
                new Setter(TemplatedControl.ForegroundProperty, Ui.Brush(Palette.Ink))
            }
        });

        var textBox = new Style(x => x.OfType<TextBox>());
        textBox.Setters.Add(new Setter(TemplatedControl.BackgroundProperty, Ui.Brush(Color.FromArgb(24, 20, 32, 27))));
        textBox.Setters.Add(new Setter(TemplatedControl.BorderBrushProperty, Ui.Brush(Palette.Hairline)));
        textBox.Setters.Add(new Setter(TemplatedControl.BorderThicknessProperty, new Thickness(1)));
        textBox.Setters.Add(new Setter(TemplatedControl.CornerRadiusProperty, new CornerRadius(9)));
        textBox.Setters.Add(new Setter(TemplatedControl.PaddingProperty, new Thickness(10, 7)));
        textBox.Setters.Add(new Setter(TemplatedControl.FontSizeProperty, 12.0));
        textBox.Setters.Add(new Setter(TemplatedControl.MinHeightProperty, 32.0));
        styles.Add(textBox);

        var combo = new Style(x => x.OfType<ComboBox>());
        combo.Setters.Add(new Setter(TemplatedControl.BackgroundProperty, Ui.Brush(Color.FromArgb(24, 20, 32, 27))));
        combo.Setters.Add(new Setter(TemplatedControl.BorderBrushProperty, Ui.Brush(Palette.Hairline)));
        combo.Setters.Add(new Setter(TemplatedControl.BorderThicknessProperty, new Thickness(1)));
        combo.Setters.Add(new Setter(TemplatedControl.CornerRadiusProperty, new CornerRadius(9)));
        combo.Setters.Add(new Setter(TemplatedControl.PaddingProperty, new Thickness(10, 6)));
        combo.Setters.Add(new Setter(TemplatedControl.FontSizeProperty, 12.0));
        combo.Setters.Add(new Setter(TemplatedControl.MinHeightProperty, 32.0));
        styles.Add(combo);

        styles.Add(new Style(x => x.OfType<ScrollViewer>())
        {
            Setters =
            {
                new Setter(TemplatedControl.BackgroundProperty, Brushes.Transparent)
            }
        });

        styles.Add(new Style(x => x.OfType<ToolTip>())
        {
            Setters =
            {
                new Setter(TemplatedControl.FontFamilyProperty, Ui.Family),
                new Setter(TemplatedControl.FontSizeProperty, 11.0)
            }
        });

        return styles;
    }
}

public static class AppBackground
{
    public static IBrush Brush => new LinearGradientBrush
    {
        StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
        EndPoint = new RelativePoint(1, 1, RelativeUnit.Relative),
        GradientStops =
        {
            new GradientStop(Color.Parse("#E9F6EE"), 0),
            new GradientStop(Color.Parse("#F6FAF7"), 0.55),
            new GradientStop(Color.Parse("#FBF6E8"), 1)
        }
    };
}
