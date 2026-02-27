# Get started

We create the gateway for mobile app.

Flutter => domain (Tunnel) => Kong => API.

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
