## Cloudflare Tunnel and CoreDNS Troubleshooting Guide

This document outlines the steps taken to troubleshoot and resolve DNS resolution issues affecting a `cloudflared` deployment and CoreDNS within a Kubernetes cluster.

### Problem Description

Initially, the `cloudflared` pod was in a `CreateContainerConfigError` state due to a missing Kubernetes Secret. After resolving that, the `cloudflared` pod started, but reported errors indicating it could not resolve internal Kubernetes service names (e.g., `keycloak-service.sso-dev.svc.cluster.local`) and later, external Cloudflare-related domains.

### Troubleshooting Steps and Resolution

#### 1. Missing Kubernetes Secret for `cloudflared`

**Symptom:** `cloudflared` pod in `CreateContainerConfigError` with error `secret "tunnel-token" not found`.

**Cause:** The `cloudflared` deployment was configured to look for a Kubernetes Secret named `tunnel-token`, but the `SecretProviderClass` was creating a Secret named `token-secret`.

**Resolution:**

1.  **Identified the `SecretProviderClass`:**
    ```bash
    kubectl get SecretProviderClass cloudflared-token -n sso-dev -o yaml
    ```

2.  **Modified the `SecretProviderClass`:** Changed the `secretName` from `token-secret` to `tunnel-token` in the `cloudflared-token` `SecretProviderClass`.
    
    *Self-correction: Initially, I tried to modify a non-existent local file. The correct approach was to get the live YAML, save it, modify it, and then apply it.* 
    
    ```bash
    # Get the current SecretProviderClass YAML
    kubectl get SecretProviderClass cloudflared-token -n sso-dev -o yaml > cloudflared-token-secretproviderclass.yaml
    
    # Manually edit cloudflared-token-secretproviderclass.yaml to change:
    # secretName: token-secret
    # to:
    # secretName: tunnel-token
    
    # Apply the modified SecretProviderClass
    kubectl apply -f cloudflared-token-secretproviderclass.yaml
    ```

3.  **Restarted `cloudflared` pods:** Deleted existing `cloudflared` pods to force recreation with the updated Secret.
    ```bash
    kubectl delete pods -l pod=cloudflared -n sso-dev
    ```

#### 2. `cloudflared` Internal DNS Resolution Failure

**Symptom:** `cloudflared` logs showed `Unable to reach the origin service: dial tcp: lookup keycloak-service.sso-dev.svc.cluster.local on 185.12.64.2:53: no such host`.

**Cause:** The `cloudflared` deployment's `dnsPolicy` was set to `Default`, causing it to inherit the node's DNS configuration, which was an external DNS server (`185.12.64.2`) that could not resolve internal Kubernetes service names.

**Resolution:**

1.  **Identified the `cloudflared` Deployment:**
    ```bash
    kubectl get deployment cloudflared-dev -n sso-dev -o yaml
    ```

2.  **Modified the `cloudflared` Deployment:** Changed the `dnsPolicy` from `Default` to `ClusterFirst` in the `cloudflared-dev` Deployment.
    
    *Self-correction: Similar to the previous step, I initially struggled with file paths. The correct approach was to get the live YAML, save it, modify it, and then apply it.* 
    
    ```bash
    # Get the current Deployment YAML
    kubectl get deployment cloudflared-dev -n sso-dev -o yaml > cloudflared-dev-deployment.yaml
    
    # Manually edit cloudflared-dev-deployment.yaml to change:
    # dnsPolicy: Default
    # to:
    # dnsPolicy: ClusterFirst
    
    # Apply the modified Deployment
    kubectl apply -f cloudflared-dev-deployment.yaml
    ```

3.  **Restarted `cloudflared` pods:** Deleted existing `cloudflared` pods to force recreation with the updated `dnsPolicy`.
    ```bash
    kubectl delete pods -l pod=cloudflared -n sso-dev
    ```

#### 3. CoreDNS External DNS Resolution Failure

**Symptom:** After resolving the internal DNS issue, `cloudflared` logs showed errors like `lookup cfd-features.argotunnel.com on 10.96.0.10:53: server misbehaving` and `i/o timeout` when trying to resolve external Cloudflare domains. A test `nslookup google.com` from a `dns-test-pod` also failed with `SERVFAIL`.

**Cause:** CoreDNS was configured to `forward . /etc/resolv.conf`, meaning it was using the node's `resolv.conf` for upstream DNS. The node's `resolv.conf` was configured to use `127.0.0.53` (a `systemd-resolved` stub resolver), which was not reachable by the CoreDNS pods. Additionally, the node's `resolv.conf` might have been pointing to misbehaving or unreachable external DNS servers.

**Resolution:**

1.  **Inspected CoreDNS `Corefile`:**
    ```bash
    kubectl get configmap coredns -n kube-system -o yaml
    ```

2.  **Modified the `coredns` ConfigMap:** Changed the `forward` plugin in the `Corefile` to use well-known public DNS servers (Google's 8.8.8.8 and 8.8.4.4) directly.
    
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

3.  **Restarted CoreDNS pods:** Deleted existing CoreDNS pods to force recreation with the updated `Corefile`.
    ```bash
    kubectl delete pods -l k8s-app=kube-dns -n kube-system
    ```

4.  **Verified external DNS resolution:** Ran `nslookup google.com` from the `dns-test-pod` again, which now successfully resolved the domain.
    ```bash
    kubectl exec dns-test-pod -n sso-dev -- nslookup google.com
    ```

### Final Verification

After all these steps, the `cloudflared` pod logs showed no more DNS resolution errors, and the tunnel connections were successfully registered. This indicates that the Cloudflare Tunnel is now correctly established and should be able to route traffic to the `keycloak-service`.

To fully verify, access `id-dev.krossform.tech` from an external network to confirm reachability of your Keycloak instance.