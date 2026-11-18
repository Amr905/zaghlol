resource "google_sql_database_instance" "this" {
  project             = var.project_id
  name                = "zaghlol-${var.environment}-pg17"
  region              = var.region
  database_version    = "POSTGRES_17"
  deletion_protection = var.deletion_protection

  settings {
    tier                        = var.tier
    edition                     = var.edition
    availability_type           = var.availability_type
    disk_type                   = "PD_SSD"
    disk_size                   = var.disk_size_gb
    disk_autoresize             = true
    deletion_protection_enabled = var.deletion_protection

    backup_configuration {
      enabled                        = true
      start_time                     = "02:00"
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = var.pitr_retention_days

      backup_retention_settings {
        retained_backups = var.retained_backups
        retention_unit   = "COUNT"
      }
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.private_network
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    maintenance_window {
      day          = 7 # Sunday
      hour         = 2
      update_track = "stable"
    }

    # Review follow-ups T-122 (security F7): row values must never reach server logs.
    database_flags {
      name  = "log_error_verbosity"
      value = "terse"
    }
    database_flags {
      name  = "log_parameter_max_length_on_error"
      value = "0"
    }
    # pgaudit for the break-glass zaghlol_ops_ro login (docs/ops/break-glass-ops-ro.md, T-140 follow-up).
    database_flags {
      name  = "cloudsql.enable_pgaudit"
      value = "on"
    }
    database_flags {
      name  = "pgaudit.log"
      value = "ddl,role"
    }
    database_flags {
      name  = "log_connections"
      value = "on"
    }
    database_flags {
      name  = "log_disconnections"
      value = "on"
    }
  }
}

resource "google_sql_database" "zaghlol" {
  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = "zaghlol"
}

# No google_sql_user for the application logins on purpose: their passwords would land in state. The operator runs
# backend/deploy/db/bootstrap-roles.sql as the built-in admin and sets the five passwords, then stores the connection
# strings in the Secret Manager secrets created by the app module (see ../../README.md, "First deploy").
