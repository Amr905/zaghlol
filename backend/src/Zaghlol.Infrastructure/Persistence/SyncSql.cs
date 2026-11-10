namespace Zaghlol.Infrastructure.Persistence;

/// <summary>
/// The part of the AddInstallLastSyncAt migration (T-128) EF can't model. Frozen with the migration: a later change goes into a
/// new migration, never here.
/// </summary>
internal static class SyncSql
{
    /// <summary>
    /// The daily-active counter increment. The sync counts its install as active in the same transaction that claims the 24 h
    /// window (T-128 design note §3), which runs on the App login; but <c>app_rw</c> keeps no privilege on
    /// <c>daily_active_counts</c> (T-122 SEC F10: it can neither read the counters nor write a count). This function is the one
    /// narrow path: it can only add 1 to one (day, platform, app version) row. SECURITY DEFINER (owner: migrator) with a fixed
    /// search_path, like the delete backstops; EXECUTE for <c>app_rw</c> only. The CHECK on <c>app_version</c> still applies.
    /// </summary>
    public const string CreateCountDailyActive = """
        CREATE FUNCTION zaghlol.count_daily_active(p_day date, p_platform text, p_app_version text) RETURNS void
          LANGUAGE plpgsql SECURITY DEFINER SET search_path = zaghlol, pg_temp AS $fn$
        BEGIN
          INSERT INTO zaghlol.daily_active_counts AS d (day, platform, app_version, installs)
          VALUES (p_day, p_platform, p_app_version, 1)
          ON CONFLICT (day, platform, app_version) DO UPDATE SET installs = d.installs + 1;
        END
        $fn$;
        REVOKE ALL ON FUNCTION zaghlol.count_daily_active(date, text, text) FROM PUBLIC;
        GRANT EXECUTE ON FUNCTION zaghlol.count_daily_active(date, text, text) TO app_rw;
        COMMENT ON FUNCTION zaghlol.count_daily_active(date, text, text) IS 'T-128: adds one install to a day''s anonymous active count; the only daily_active_counts write of app_rw.';
        """;

    public const string DropCountDailyActive = "DROP FUNCTION zaghlol.count_daily_active(date, text, text);";
}
