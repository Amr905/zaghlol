# Key custody for the Gold design (deployment section 3, T-140).
#
# - No role below grants cloudkms.cryptoKeyVersions.export or import: Cloud KMS signing, MAC and encrypt keys are never
#   exportable, so the API identity can use a key but not read its material.
# - HMAC keys (K_seat, K_audit, install_hash pepper) are pinned to version 1, have no rotation_period, and carry
#   prevent_destroy: a silently changed HMAC key orphans every stored keyed hash.
# - Signing keys also have no rotation_period. A rotation is a NEW key (a new kid) added to var.signing_keys, with the next
#   public key shipped in the app one release earlier.

resource "google_kms_key_ring" "this" {
  project  = var.project_id
  name     = "zaghlol-${var.environment}"
  location = var.location
}

resource "google_kms_crypto_key" "signing" {
  for_each = var.signing_keys

  name                       = "sign-${each.key}"
  key_ring                   = google_kms_key_ring.this.id
  purpose                    = "ASYMMETRIC_SIGN"
  destroy_scheduled_duration = "2592000s" # 30 days
  labels                     = merge(var.labels, { purpose = lower(each.value.purpose) })

  version_template {
    algorithm        = "EC_SIGN_P256_SHA256"
    protection_level = var.signing_protection_level
  }

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  hmac_keys = {
    seat                = "hmac-kseat"
    audit               = "hmac-kaudit"
    install_hash_pepper = "hmac-install-hash-pepper"
  }
}

resource "google_kms_crypto_key" "hmac" {
  for_each = local.hmac_keys

  name                       = each.value
  key_ring                   = google_kms_key_ring.this.id
  purpose                    = "MAC"
  destroy_scheduled_duration = "2592000s"
  labels                     = var.labels

  version_template {
    algorithm        = "HMAC_SHA256"
    protection_level = var.hmac_protection_level
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_kms_crypto_key" "envelope" {
  name                       = "envelope"
  key_ring                   = google_kms_key_ring.this.id
  purpose                    = "ENCRYPT_DECRYPT"
  destroy_scheduled_duration = "2592000s"
  labels                     = var.labels

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = var.signing_protection_level
  }

  lifecycle {
    prevent_destroy = true
  }
}

# --- least-privilege bindings, per key (never on the key ring or project) ---

resource "google_kms_crypto_key_iam_member" "api_sign" {
  for_each = google_kms_crypto_key.signing

  crypto_key_id = each.value.id
  role          = "roles/cloudkms.signerVerifier" # sign, verify, view public key
  member        = "serviceAccount:${var.api_service_account}"
}

resource "google_kms_crypto_key_iam_member" "api_hmac" {
  for_each = google_kms_crypto_key.hmac

  crypto_key_id = each.value.id
  role          = "roles/cloudkms.signerVerifier" # MacSign / MacVerify
  member        = "serviceAccount:${var.api_service_account}"
}

resource "google_kms_crypto_key_iam_member" "api_envelope" {
  crypto_key_id = google_kms_crypto_key.envelope.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${var.api_service_account}"
}

resource "google_kms_crypto_key_iam_member" "worker_envelope" {
  crypto_key_id = google_kms_crypto_key.envelope.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${var.worker_service_account}"
}
