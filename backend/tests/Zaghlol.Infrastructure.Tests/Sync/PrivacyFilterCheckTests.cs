using Zaghlol.Application.Contributions;
using Zaghlol.Application.Sync;
using Zaghlol.Infrastructure.Persistence.Configurations;

namespace Zaghlol.Infrastructure.Tests.Sync;

/// <summary>
/// The API filter is the control and the database CHECK only a backstop (T-122 F7, FU-018, T-128 S1): every text the sync would
/// store (normalized and accepted by <see cref="ContributionPrivacy"/>) satisfies the CHECK, evaluated by PostgreSQL itself.
/// </summary>
[Collection(SchemaGroup.Name)]
public class PrivacyFilterCheckTests(SchemaFixture fixture)
{
    // Digits the CHECK knows and digits it doesn't, the CHECK's separators and others, letters, marks, format characters and
    // at signs. All synthetic.
    private static readonly string[] Alphabet =
    [
        "0", "1", "5", "9", "٠", "٥", "۳", "１", "१", "২", "\U0001D7D0", "²", "₃", "④",
        " ", "  ", "\t", ".", ",", "/", "_", "،", "-", "–", "−", "ـ", "•", "|", ":", "(", ")", "·",
        "a", "B", "ك", "م", "́", "َ", "⃣", "​", "‏", "@", "﹫", "＠", "　",
    ];

    [Fact]
    public async Task EveryTextTheFilterAcceptsPassesTheDatabaseCheck()
    {
        var state = 128u;
        int Next(int bound) => (int)(((state = (state * 1664525u) + 1013904223u) >> 8) % (uint)bound); // fixed-seed LCG

        var raw = new List<string>();
        var stored = new List<string>();
        for (var i = 0; i < 20_000; i++)
        {
            var text = string.Concat(Enumerable.Range(0, 1 + Next(23)).Select(_ => Alphabet[Next(Alphabet.Length)]));
            raw.Add(text);
            if (SyncIntake.NormalizeText(text) is { } normalized && ContributionPrivacy.IsAcceptable(normalized))
            {
                stored.Add(normalized);
            }
        }

        var check = CheckSql.PrivacySafeNorm("x");
        var violations = await Db.QueryAsync(
            fixture.Database.Superuser,
            $"SELECT x FROM unnest($1::text[]) AS u(x) WHERE NOT ({check})",
            (object)stored.ToArray());

        Assert.Empty(violations.Select(r => (string)r[0]!));

        // The generator is meaningful: the CHECK rejects many raw texts, and the filter still keeps some.
        var rejectedRaw = (long)(await Db.ScalarAsync(
            fixture.Database.Superuser,
            $"SELECT count(*) FROM unnest($1::text[]) AS u(x) WHERE NOT ({check})",
            (object)raw.ToArray()))!;
        Assert.True(rejectedRaw > 100, $"{rejectedRaw} raw texts rejected by the CHECK");
        Assert.True(stored.Count > 100, $"{stored.Count} texts accepted by the filter");
    }
}
