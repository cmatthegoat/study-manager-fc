using System.Text.Json;
using System.Text.Json.Serialization;

namespace StudyManagerFC.Core;

/// <summary>
/// Reads and writes the same career.json the macOS build produces: camel-cased keys,
/// ISO-8601 timestamps without fractional seconds, string enums and upper-case UUIDs.
/// </summary>
public static class SaveJson
{
    public static JsonSerializerOptions Options { get; } = CreateOptions();

    private static JsonSerializerOptions CreateOptions()
    {
        var options = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            PropertyNameCaseInsensitive = true,
            WriteIndented = false,
            DefaultIgnoreCondition = JsonIgnoreCondition.Never
        };
        options.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.CamelCase));
        options.Converters.Add(new Iso8601DateTimeConverter());
        options.Converters.Add(new UpperCaseGuidConverter());
        return options;
    }
}

public sealed class Iso8601DateTimeConverter : JsonConverter<DateTimeOffset>
{
    public override DateTimeOffset Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        var text = reader.GetString();
        if (string.IsNullOrWhiteSpace(text)) return default;
        if (DateTimeOffset.TryParse(text, System.Globalization.CultureInfo.InvariantCulture,
                System.Globalization.DateTimeStyles.RoundtripKind, out var parsed))
        {
            return parsed;
        }
        throw new JsonException($"Unrecognised timestamp '{text}'.");
    }

    public override void Write(Utf8JsonWriter writer, DateTimeOffset value, JsonSerializerOptions options)
    {
        writer.WriteStringValue(value.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", System.Globalization.CultureInfo.InvariantCulture));
    }
}

public sealed class UpperCaseGuidConverter : JsonConverter<Guid>
{
    public override Guid Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        var text = reader.GetString();
        return Guid.TryParse(text, out var parsed) ? parsed : Guid.Empty;
    }

    public override void Write(Utf8JsonWriter writer, Guid value, JsonSerializerOptions options)
    {
        writer.WriteStringValue(value.ToString().ToUpperInvariant());
    }
}

public sealed class PersistenceStore
{
    public string Directory { get; }
    public string SavePath { get; }

    public PersistenceStore(string? baseDirectory = null)
    {
        var overrideDirectory = Environment.GetEnvironmentVariable("SMFC_SAVE_DIR");
        var root = baseDirectory
            ?? (string.IsNullOrWhiteSpace(overrideDirectory) ? null : overrideDirectory)
            ?? Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "StudyManagerFC");
        Directory = root;
        SavePath = Path.Combine(root, "career.json");
    }

    public GameState? Load()
    {
        if (!File.Exists(SavePath)) return null;
        var data = File.ReadAllText(SavePath);
        try
        {
            return JsonSerializer.Deserialize<GameState>(data, SaveJson.Options);
        }
        catch (JsonException)
        {
            PreserveCorruptSave();
            throw;
        }
    }

    public void Save(GameState state)
    {
        System.IO.Directory.CreateDirectory(Directory);
        var json = JsonSerializer.Serialize(state, SaveJson.Options);
        var temp = SavePath + ".tmp";
        File.WriteAllText(temp, json);
        File.Move(temp, SavePath, true);
    }

    private void PreserveCorruptSave()
    {
        try
        {
            var backup = Path.Combine(Directory, $"career-corrupt-{DateTimeOffset.UtcNow.ToUnixTimeSeconds()}.json");
            File.Copy(SavePath, backup, true);
        }
        catch (IOException)
        {
            // Nothing more we can do; the caller reports the read failure.
        }
    }
}
