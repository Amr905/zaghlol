# Pinned key-version references (immutable), in the shape of the Kms:* / Signing:Keys:* configuration.

output "signing_keys" {
  description = "kid => { purpose, key_ref (CryptoKeyVersion 1) }. PublicJwk is derived after apply (see ../../README.md)."
  value = {
    for kid, k in google_kms_crypto_key.signing : kid => {
      purpose = var.signing_keys[kid].purpose
      key_ref = "${k.id}/cryptoKeyVersions/1"
    }
  }
}

output "hmac_key_refs" {
  description = "Pinned HMAC key versions for Kms:HmacKeys:{Seat, Audit, InstallHashPepper}."
  value = {
    Seat              = "${google_kms_crypto_key.hmac["seat"].id}/cryptoKeyVersions/1"
    Audit             = "${google_kms_crypto_key.hmac["audit"].id}/cryptoKeyVersions/1"
    InstallHashPepper = "${google_kms_crypto_key.hmac["install_hash_pepper"].id}/cryptoKeyVersions/1"
  }
}

output "envelope_key_ref" {
  description = "Kms:Envelope:KeyRef (the key, not a version: GCP wraps with the primary version)."
  value       = google_kms_crypto_key.envelope.id
}

output "key_ring_id" {
  value = google_kms_key_ring.this.id
}
