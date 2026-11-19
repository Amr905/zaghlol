# OpenBao server configuration for the Zaghlol Transit KMS (T-201; design note §7, deployment.md §3 "OpenBao Transit KMS").
# Mounted read-only at /openbao/config. Paths below are inside the OpenBao container; see docker-compose.openbao.yml.

ui            = false
disable_mlock = true # required with raft storage; run the host without swap or with encrypted swap (deployment.md §3)

# Reachable only on the stack's private network (no published port). The certificate's names must include "openbao".
api_addr     = "https://openbao:8200"
cluster_addr = "https://openbao:8201"

storage "raft" {
  path    = "/openbao/data"
  node_id = "zaghlol-1"
}

listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_cert_file   = "/openbao/tls/server.pem"
  tls_key_file    = "/openbao/tls/server-key.pem"
  tls_min_version = "tls12"
}

# Auto-unseal with a 32-byte key file (OpenBao >= 2.4). The file is root-controlled on the host, readable only by the
# OpenBao container's user, never mounted into the api or worker; two offline encrypted copies (deployment.md §3).
# Rotation: write the new key to a new file, set it as current_key with a new id, move the old one to previous_key, restart.
seal "static" {
  current_key_id = "zaghlol-unseal-1"
  current_key    = "file:///openbao/unseal/unseal.key"
}

# Every request and response, secret fields HMAC'd (the default). Audit devices are declared here; creating them through
# the API stays off (no unsafe_allow_api_audit_creation).
audit "file" "zaghlol-file" {
  description = "Zaghlol KMS audit log (T-201)"
  options {
    file_path = "/openbao/audit/audit.log"
    mode      = "0600"
  }
}
