namespace Zaghlol.Infrastructure.Persistence;

/// <summary>
/// The database login a process uses. Each maps to <c>ConnectionStrings:&lt;name&gt;</c> and to one group role of
/// <c>backend/deploy/db/bootstrap-roles.sql</c>, so an injection in one endpoint group can't use another group's grants.
/// </summary>
public enum DatabaseRole
{
    /// <summary><c>ConnectionStrings:App</c>, login <c>zaghlol_api</c> in group <c>app_rw</c>: the public <c>/v1/*</c> endpoints.</summary>
    App,

    /// <summary><c>ConnectionStrings:Admin</c>, login <c>zaghlol_admin</c> in group <c>ops_rw</c>: the <c>/admin/v1/*</c> endpoints.</summary>
    Admin,

    /// <summary><c>ConnectionStrings:Worker</c>, login <c>zaghlol_worker</c> in group <c>worker_rw</c>: background jobs.</summary>
    Worker,

    /// <summary><c>ConnectionStrings:Migrator</c>, login <c>migrator</c>: the migration job only (owns the schema).</summary>
    Migrator,
}
