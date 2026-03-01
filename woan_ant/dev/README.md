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

## Setup Kubernetes

Let state with setup the kubernetes property.

### 1-Create name space

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: one-gateway-dev
```

```kubectl apply -f dev-name-space.yaml```

### 2-Create deployment

We will use busy box for testing purpose.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: testing-dev-deployment
  namespace: one-gateway-dev
  labels:
    app: testing-dev-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: testing-dev-deployment
  template:
    metadata:
      labels:
        app: testing-dev-deployment
    spec:
      containers:
        - name: grad
          image: rslim087/kubernetes-course-grade-submission-api:stateless
          ports:
          - containerPort: 3000
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "100m"
              memory: "128Mi"
```

```kubectl apply -f testing-dev-deployment.yaml```

### 3-Create services

```yaml
apiVersion: v1
kind: Service
metadata:
  name: one-gateway-dev-service
  namespace: one-gateway-dev
spec:
  type: ClusterIP
  selector:
    app: testing-dev-deployment # will change to the real one
  ports:
    - name: http
      port: 3000
      targetPort: 3000
```

```kubectl apply -f testing-dev-service.yaml```

### 4-Create ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: one-gateway-ingress-dev
  namespace: one-gateway-dev
  annotations:
    konghq.com/strip-path: "true"
  ingressClassName: kong
  rules:
  - host: gateway-dev.1digital.app
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: one-gateway-service-dev
            port:
              number: 3000
```

```kubectl apply -f one-gateway-ingress-dev.yaml```

## Vault

Create vault policy

```bash
# Read access to actual secret data
path "woan-ant/data/cloudflare/dev/one-gateway-dev-tunnel-token" {
  capabilities = ["read"]
}

# List access to metadata (required to see what exists)
path "woan-ant/metadata/cloudflare/dev/one-gateway-dev-tunnel-token" {
  capabilities = ["list"]
}
```

then write the policy to vault

```bash
vault policy write one-gateway-dev one-gateway-dev.hcl
```

## Kubernetes

Create service account:

```bash
kubectl create serviceaccount one-gateway-dev-sa -n one-gateway-dev
```

Create Vault Kubernetes auth role

```bash
vault write auth/kubernetes/role/one-gateway-role-dev \
  bound_service_account_names=one-gateway-sa-dev \
  bound_service_account_namespaces=one-gateway-dev \
  policies=one-gateway-policy-dev \
  ttl=24h
```

Verification of the Kubernetes Auth Method in Vault: (can be skip)

* use kubectl create the token:

```bash
kubectl create token one-gateway-sa-dev -n one-gateway-dev
```

* generate vault token:

```bash
vault write auth/kubernetes/login \
role=<role> \
jwt=<token>
```

Create vault secret provider

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: cloudflared-token
  namespace: one-gateway-dev
spec:
  provider: vault
  secretObjects:
    - secretName: "token-secret"
      type: Opaque
      data:
        - objectName: "token"
          key: "token"
  parameters:
    roleName: "one-gateway-role-dev"
    vaultSkipTLSVerify: "true"
    objects: |
      - secretPath: "woan-ant/data/cloudflare/dev/one-gateway-dev-tunnel-token"
        objectName: "token"
        secretKey: "token"
```

```kubectl apply -f vault-csi-provider.yaml```

## Cloudflare

### 1-Create tunnel

Login to cloudflare => Network => Tunnel, then create new tunnel for dev environment

I called it one-gateway-dev then put the token in to vault;

```bash
vault kv put woan-ant/cloudflare/dev/one-gateway-dev-tunnel-token token="xxx"
```

**Note**:

When create tunnel in cloudflare we need to finish the creation by running connect command the first time:

```bash
cloudflared tunnel run --token xxx
```

### 2-Configuration

Add route from gateway-dev.1digital.app to the cluster url service which is http://one-gateway-service-dev.one-gateway-dev.svc.cluster.local:3000

### 3-Create cloudflare tunnel deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cloudflared-dev
  namespace: one-gateway-dev
spec:
  replicas: 1
  selector:
    matchLabels:
      pod: cloudflared
  template:
    metadata:
      labels:
        pod: cloudflared
    spec:
      serviceAccountName: one-gateway-sa-dev
      dnsPolicy: ClusterFirst
      containers:
        - name: cloudflared
          image: cloudflare/cloudflared:2025.11.1
          env:
            - name: TUNNEL_TOKEN
              valueFrom:
                secretKeyRef:
                  name: token-secret
                  key: token
          command:
            - cloudflared
            - tunnel
            - --no-autoupdate
            - --loglevel
            - debug
            - --metrics
            - 0.0.0.0:2000
            - run
            # - --token
            # - "$(TUNNEL_TOKEN)"
          resources:
            requests:
              cpu: 100m
              memory: 64Mi
            limits:
              cpu: 500m
              memory: 256Mi
          volumeMounts:
            - name: "cloudflared-token"
              mountPath: "/mnt/secrets-store"
              readOnly: true
      volumes:
        - name: cloudflared-token
          csi:
            driver: secrets-store.csi.k8s.io
            readOnly: true
            volumeAttributes:
              secretProviderClass: "cloudflared-token"
```

```kubectl apply -f one-gateway-cloudflared-dev.yaml```
