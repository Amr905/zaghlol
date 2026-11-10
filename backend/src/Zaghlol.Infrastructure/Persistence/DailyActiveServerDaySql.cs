namespace Zaghlol.Infrastructure.Persistence;

/// <summary>
/// The CountDailyActiveServerDay migration (T-128 security review S3). Frozen with the migration: a later change goes into a
/// new migration, never here. <see cref="SyncSql"/> stays frozen too; its old function is what <see cref="Down"/> restores.
/// </summary>
internal static class DailyActiveServerDaySql
{
    /// <summary>
    /// Replaces <c>count_daily_active(date, text, text)</c> with <c>count_daily_active(text, text)</c>: the day is the database's
    /// own UTC date of the transaction (<c>now()</c>), so <c>app_rw</c> can no longer add to a past or future day, and the
    /// platform must be <c>android</c> or <c>ios</c> (SQLSTATE 22023 otherwise; the message carries no argument). Everything
    /// else is unchanged: SECURITY DEFINER (owner: migrator), fixed search_path, a single static upsert that can only add 1,
    /// REVOKEd from PUBLIC, EXECUTE for <c>app_rw</c> only.
    /// </summary>
    public const string Up = """
        DROP FUNCTION zaghlol.count_daily_active(date, text, text);
        CREATE FUNCTION zaghlol.count_daily_active(p_platform text, p_app_version text) RETURNS void
          LANGUAGE plpgsql SECURITY DEFINER SET search_path = zaghlol, pg_temp AS $fn$
        BEGIN
          IF p_platform IS NULL OR p_platform NOT IN ('android', 'ios') THEN
            RAISE EXCEPTION 'count_daily_active: unknown platform' USING ERRCODE = '22023';
          END IF;
          INSERT INTO zaghlol.daily_active_counts AS d (day, platform, app_version, installs)
          VALUES ((now() AT TIME ZONE 'UTC')::date, p_platform, p_app_version, 1)
          ON CONFLICT (day, platform, app_version) DO UPDATE SET installs = d.installs + 1;
        END
        $fn$;
        REVOKE ALL ON FUNCTION zaghlol.count_daily_active(text, text) FROM PUBLIC;
        GRANT EXECUTE ON FUNCTION zaghlol.count_daily_active(text, text) TO app_rw;
        COMMENT ON FUNCTION zaghlol.count_daily_active(text, text) IS 'T-128: adds one install to today''s (UTC) anonymous active count for android or ios; the only daily_active_counts write of app_rw.';
        """;

    /// <summary>Restores the function of AddInstallLastSyncAt.</summary>
    public const string Down = "DROP FUNCTION zaghlol.count_daily_active(text, text);\n" + SyncSql.CreateCountDailyActive;
}
