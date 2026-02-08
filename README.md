# Kong

## 1 . Installation

### 1 . 1 add helm repo

```bash
helm repo add kong <https://charts.konghq.com> && helm repo update
```

### 1 .2 create namespace

```bash
kubectl create namespace kong
```

### 1 . 3 install helm chart

```bash
helm install kong kong/kong -n kong
```

### 1 . 4 install MetalLB as load-balancer

if there is no load-balancer we need to install one, if have just skip this step.

```bash
helm repo add metallb https://metallb.github.io/metallb && helm repo update
```

```bash
helm install metallb metallb/metallb -n metallb-system --create-namespace
```

### 1 . 5 set the rang ip for metallb

note please use the ip range that not in use.

if kubernetes is use 10.0.0.2 and other server is the same range like 10.0.0.3 ....

we should set it for this range 10.0.0.101-10.0.0.120.

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - 10.0.0.101-10.0.0.120
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default-advertisement
  namespace: metallb-system
  ```

then apply

```bash
kubectl apply -f metallb-config.yaml
```

## 2 . Ingress and Services

Next we have to create the service for keycloak.(keycloak-service.yaml)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: keycloak-service
  namespace: sso-dev
spec:
  type: ClusterIP
  selector:
    app: keycloak-dev
  ports:
    - name: http
      port: 8080
      targetPort: 8080
```

Then apply it.

Next create the ingress for keycloak.(keycloak-ingress.yaml)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: keycloak-ingress
  namespace: sso-dev
  annotations:
    konghq.com/strip-path: 'true'
spec:
  ingressClassName: kong
  rules:
  - host: id-dev.krossform.tech
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: keycloak-service
            port:
              number: 8080
```

Then apply it.

## 3 . Inspected CoreDNS `Corefile`

```bash kubectl get configmap coredns -n kube-system -o yaml```

## 4. **Modified the `coredns` ConfigMap:** Changed the `forward` plugin in the `Corefile` to use well-known public DNS servers (Google's 8.8.8.8 and 8.8.4.4) directly

*Self-correction: Again, saved the live YAML, modified it, and applied it.*

```bash
    # Get the current ConfigMap YAML
    kubectl get configmap coredns -n kube-system -o yaml > coredns-configmap.yaml
    
    # Manually edit coredns-configmap.yaml to change:
    #         forward . /etc/resolv.conf {
    # to:
    #         forward . 8.8.8.8 8.8.4.4 {
    
    # Apply the modified ConfigMap
    kubectl apply -f coredns-configmap.yaml
```

full yaml file:

```yaml
apiVersion: v1
data:
  Corefile: |
    .:53 {
        errors
        health {
           lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
           ttl 30
        }
        prometheus :9153
        forward . 8.8.8.8 8.8.4.4 {
           max_concurrent 1000
        }
        cache 30 {
           disable success cluster.local
           disable denial cluster.local
        }
        loop
        reload
        loadbalance
    }
kind: ConfigMap
metadata:
  creationTimestamp: "2025-08-07T15:07:42Z"
  name: coredns
  namespace: kube-system
  resourceVersion: "241"
  uid: 7c9e433c-773e-44fa-a807-6a7865d2c77e
```

### 4 . **Restarted CoreDNS pods:** Deleted existing CoreDNS pods to force recreation with the updated `Corefile`

```bash
    kubectl delete pods -l k8s-app=kube-dns -n kube-system
```
