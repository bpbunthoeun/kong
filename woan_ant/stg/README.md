# Get started

We create the gateway for mobile app.
Because of our infrastructure in under cloudflare, some of the feature like ratelimited kong not working well, so we need check some thing first.
Flutter => domain (Tunnel) => Kong => API.

## Kong

### Rate limited

**Note**:
Kong installed via helm

Check the current value and configuration.
ssh to master server (control plan)

backup first

```bash
helm get values kong -n kong -o yaml > kong-values-backup.yaml
```

So want to rollback:

### Option 1

Check revision history

```bash
helm history kong -n kong
 ```

Rollback to previous revision

```bash
helm rollback kong 1 -n kong
```

example:

1 is version number, then we can change it accordingly

### Option 2

Rollback Using Your Backup Values File

```bash
helm upgrade kong kong/kong \
  -n kong \
  -f /root/backup/kong/values/kong-values-28-02-2026.yaml
```

⚠️ Important:

kong/kong must match the chart you originally installed

If you used a custom repo version, you must specify --version.

### Update Kong current version with value

Next, because user cloudflare we need to setup cloudflare based on value as below:

Inside our master plan.

Step 1 — Create override file

```bash
nano kong-realip.yaml
```

Paste:

env:
  trusted_ips: >-
    127.0.0.1/32, # kubernetes ip range
    192.168.0.0/16, # kubernetes ip range
    10.0.0.0/8, # kubernetes ip range
    172.16.0.0/12, # kubernetes ip range
    173.245.48.0/20,
    103.21.244.0/22,
    103.22.200.0/22,
    103.31.4.0/22,
    141.101.64.0/18,
    108.162.192.0/18,
    190.93.240.0/20,
    188.114.96.0/20,
    197.234.240.0/22,
    198.41.128.0/17,
    162.158.0.0/15,
    104.16.0.0/13,
    104.24.0.0/14,
    172.64.0.0/13,
    131.0.72.0/22,
    2400:cb00::/32,
    2606:4700::/32,
    2803:f800::/32,
    2405:b500::/32,
    2405:8100::/32,
    2a06:98c0::/29,
    2c0f:f248::/32
  real_ip_header: CF-Connecting-IP
  real_ip_recursive: "on"

**Note**:
This IP range are belong to kubernetes:
    127.0.0.1/32, # kubernetes ip range
    192.168.0.0/16, # kubernetes ip range
    10.0.0.0/8, # kubernetes ip range
    172.16.0.0/12, # kubernetes ip range

Save.

Step 2 — Upgrade Helm

You installed from kong/kong chart, so run:

```bash
helm upgrade kong kong/kong \
  -n kong \
  --reuse-values \
  -f kong-realip.yaml
  ```

Important:

--reuse-values keeps all current config

-f merges new env settings

## Cloudflare

### Rate-limited

Cloudflare is edg to edg protection that we use.

Go to Domain => Security => Security role

Create new role for rate limited

### Setup Kubernetes

Let state with setup the kubernetes property.

### 1-Create name space

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: one-gateway-stg
```

```kubectl apply -f stg-name-space.yaml```

