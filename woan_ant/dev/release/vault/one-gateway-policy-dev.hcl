# Read access to actual secret data
path "woan-ant/data/cloudflare/dev/one-gateway-dev-tunnel-token" {
  capabilities = ["read"]
}

# List access to metadata (required to see what exists)
path "woan-ant/metadata/cloudflare/dev/one-gateway-dev-tunnel-token" {
  capabilities = ["list"]
}