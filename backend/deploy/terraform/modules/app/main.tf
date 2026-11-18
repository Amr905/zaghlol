locals {
  prefix = "zaghlol-${var.environment}"

  # Secret Manager secrets are created EMPTY. The operator adds the versions; no secret value is ever in code or state.
  secrets = {
    conn_app         = { id = "${local.prefix}-conn-app", env = "ConnectionStrings__App" }
    conn_admin       = { id = "${local.prefix}-conn-admin", env = "ConnectionStrings__Admin" }
    conn_worker      = { id = "${local.prefix}-conn-worker", env = "ConnectionStrings__Worker" }
    conn_migrator    = { id = "${local.prefix}-conn-migrator", env = "ConnectionStrings__Migrator" }
    apple_issuer_id  = { id = "${local.prefix}-apple-issuer-id", env = "Purchases__Apple__IssuerId" }
    apple_key_id     = { id = "${local.prefix}-apple-key-id", env = "Purchases__Apple__KeyId" }
    apple_private    = { id = "${local.prefix}-apple-private-key", env = "Purchases__Apple__PrivateKey" }
    ops_webhook_url  = { id = "${local.prefix}-ops-webhook-url", env = "OpsChannel__WebhookUrl" }
    apple_acct_key   = { id = "${local.prefix}-apple-signin-private-key", env = "Accounts__Apple__PrivateKey" }
    apple_acct_keyid = { id = "${local.prefix}-apple-signin-key-id", env = "Accounts__Apple__KeyId" }
  }

  api_secret_keys    = ["conn_app", "conn_admin", "apple_issuer_id", "apple_key_id", "apple_private", "ops_webhook_url", "apple_acct_key", "apple_acct_keyid"]
  worker_secret_keys = ["conn_worker", "apple_issuer_id", "apple_key_id", "apple_private", "apple_acct_key", "apple_acct_keyid"]

  signing_kids = sort(keys(var.kms_signing_keys))

  signing_env = merge([
    for idx, kid in local.signing_kids : {
      "Signing__Keys__${idx}__Kid"     = kid
      "Signing__Keys__${idx}__Purpose" = var.kms_signing_keys[kid].purpose
      "Signing__Keys__${idx}__Status"  = lookup(var.signing_key_status, kid, "Active")
      "Signing__Keys__${idx}__KeyRef"  = var.kms_signing_keys[kid].key_ref
    }
  ]...)

  forwarded_env = {
    for idx, cidr in var.forwarded_headers_known_networks : "ForwardedHeaders__KnownNetworks__${idx}" => cidr
  }

  api_env = merge(
    var.app_settings,
    local.signing_env,
    local.forwarded_env,
    {
      ASPNETCORE_ENVIRONMENT                              = var.aspnet_environment
      Kms__Provider                                       = var.kms_provider
      Kms__HmacKeys__Seat                                 = var.kms_hmac_key_refs.Seat
      Kms__HmacKeys__Audit                                = var.kms_hmac_key_refs.Audit
      Kms__HmacKeys__InstallHashPepper                    = var.kms_hmac_key_refs.InstallHashPepper
      Kms__HmacKeys__SeatCheck                            = var.kseat_check_hex
      Kms__Envelope__KeyRef                               = var.kms_envelope_key_ref
      Purchases__Google__CredentialSource                 = "ApplicationDefault"
      Rtdn__Audience                                      = var.rtdn.audience
      Rtdn__PushServiceAccount                            = var.rtdn.push_service_account
      Rtdn__Subscription                                  = var.rtdn.subscription
      Attestation__AppAttest__AllowDevelopmentEnvironment = var.environment == "staging" ? "true" : "false"
    },
  )

  worker_env = merge(
    var.app_settings,
    {
      ASPNETCORE_ENVIRONMENT              = var.aspnet_environment
      DOTNET_ENVIRONMENT                  = var.aspnet_environment
      Kms__Provider                       = var.kms_provider
      Kms__Envelope__KeyRef               = var.kms_envelope_key_ref
      Purchases__Google__CredentialSource = "ApplicationDefault"
    },
  )
}

resource "google_secret_manager_secret" "this" {
  for_each = local.secrets

  project   = var.project_id
  secret_id = each.value.id

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret_iam_member" "api" {
  for_each = toset(local.api_secret_keys)

  project   = var.project_id
  secret_id = google_secret_manager_secret.this[each.key].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.api_service_account}"
}

resource "google_secret_manager_secret_iam_member" "worker" {
  for_each = toset(local.worker_secret_keys)

  project   = var.project_id
  secret_id = google_secret_manager_secret.this[each.key].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.worker_service_account}"
}

resource "google_secret_manager_secret_iam_member" "migrator" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.this["conn_migrator"].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.migrator_service_account}"
}

# --- API: public /v1/* and operator /admin/v1/*, reachable only through the load balancer ---

resource "google_cloud_run_v2_service" "api" {
  project              = var.project_id
  name                 = "${local.prefix}-api"
  location             = var.region
  ingress              = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
  default_uri_disabled = true
  deletion_protection  = var.deletion_protection

  template {
    service_account                  = var.api_service_account
    timeout                          = "30s"
    max_instance_request_concurrency = 40

    scaling {
      min_instance_count = var.api_min_instances
      max_instance_count = var.api_max_instances
    }

    vpc_access {
      egress = "PRIVATE_RANGES_ONLY"
      network_interfaces {
        network    = var.network_id
        subnetwork = var.subnet_name
      }
    }

    containers {
      image = var.image

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = var.api_cpu
          memory = var.api_memory
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      # /v1/health is READINESS (database reachable). It is used only to decide that a new revision may take traffic.
      # There is deliberately no liveness probe on it (review T-122 code #8 / security F14): a database outage must not
      # restart healthy API instances. Cloud Run restarts a container whose process exits.
      startup_probe {
        http_get {
          path = "/v1/health"
        }
        period_seconds    = 5
        timeout_seconds   = 3
        failure_threshold = 12
      }

      dynamic "env" {
        for_each = local.api_env
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = toset(local.api_secret_keys)
        content {
          name = local.secrets[env.value].env
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.this[env.value].secret_id
              version = "latest"
            }
          }
        }
      }
    }
  }

  depends_on = [
    google_secret_manager_secret_iam_member.api,
  ]
}

# The load balancer does not authenticate; ingress is restricted to it, and the app authenticates every caller itself.
resource "google_cloud_run_v2_service_iam_member" "api_public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# --- Worker: one replica (PostgreSQL advisory-lock singletons; Budget:WorkerReplicas defaults to 1) ---
# A Cloud Run worker pool has no HTTP endpoint and no exec probe, so the heartbeat-file health check of the image
# (Worker__HeartbeatFile, `--healthcheck`) cannot be used here; a crashed process is restarted by the platform and the
# alert rules in backend/deploy/observability/alerts/platform.yaml watch the heartbeat metric.

resource "google_cloud_run_v2_worker_pool" "worker" {
  project             = var.project_id
  name                = "${local.prefix}-worker"
  location            = var.region
  deletion_protection = var.deletion_protection

  scaling {
    scaling_mode          = "MANUAL"
    manual_instance_count = 1
  }

  template {
    service_account = var.worker_service_account

    vpc_access {
      egress = "PRIVATE_RANGES_ONLY"
      network_interfaces {
        network    = var.network_id
        subnetwork = var.subnet_name
      }
    }

    containers {
      image   = var.image
      command = ["dotnet", "/app/worker/Zaghlol.Workers.dll"]

      resources {
        limits = {
          cpu    = var.worker_cpu
          memory = var.worker_memory
        }
      }

      dynamic "env" {
        for_each = local.worker_env
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = toset(local.worker_secret_keys)
        content {
          name = local.secrets[env.value].env
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.this[env.value].secret_id
              version = "latest"
            }
          }
        }
      }
    }
  }

  depends_on = [
    google_secret_manager_secret_iam_member.worker,
  ]
}

# --- Migration job: same image, `--migrate`, run by the deploy workflow BEFORE the new API revision gets traffic ---

resource "google_cloud_run_v2_job" "migrate" {
  project             = var.project_id
  name                = "${local.prefix}-migrate"
  location            = var.region
  deletion_protection = var.deletion_protection

  template {
    task_count = 1

    template {
      service_account = var.migrator_service_account
      max_retries     = 0
      timeout         = "600s"

      vpc_access {
        egress = "PRIVATE_RANGES_ONLY"
        network_interfaces {
          network    = var.network_id
          subnetwork = var.subnet_name
        }
      }

      containers {
        image   = var.image
        command = ["dotnet", "/app/worker/Zaghlol.Workers.dll"]
        args    = ["--migrate"]

        resources {
          limits = {
            cpu    = "1"
            memory = "512Mi"
          }
        }

        env {
          name  = "ASPNETCORE_ENVIRONMENT"
          value = var.aspnet_environment
        }

        env {
          name = local.secrets["conn_migrator"].env
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.this["conn_migrator"].secret_id
              version = "latest"
            }
          }
        }
      }
    }
  }

  depends_on = [
    google_secret_manager_secret_iam_member.migrator,
  ]
}
