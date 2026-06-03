# Wildcard TLS Certificate via Let's Encrypt and Cloudflare DNS-01

Below is how a wildcard TLS certificate is issued and managed in this homelab using cert-manager, Let's Encrypt, and Cloudflare DNS-01 challenge (see [cert-manager DNS-01 docs](https://cert-manager.io/docs/configuration/acme/dns01/)).

In this setup the domain (`pgermani.dev`) is registered directly on Cloudflare, which allows using their DNS API for DNS-01 challenges without any additional provider configuration. cert-manager handles the full certificate lifecycle, issuance and renewal.

The resulting certificate secret is replicated to all namespaces via Reflector (see [reflector.md](reflector.md)), so every workload can reference it without additional setup.

---

## 1. Prerequisites

| Requirement | Details |
|---|---|
| cert-manager installed | See [cert-manager.md](cert-manager.md) |
| Reflector installed | See [reflector.md](reflector.md) |
| Domain registered on Cloudflare | DNS must be managed by Cloudflare |

---

## 2. Create a Cloudflare API Token

In the Cloudflare dashboard, navigate to **My Profile -> API Tokens** and click **Create Token -> Custom Token**.

Configure the token as follows:

| Field | Value |
|---|---|
| Token name | e.g. `letsEncrypt` |
| Permissions | Zone -> DNS -> Edit |
| Zone Resources | Include -> Specific Zone -> `<YOUR-DOMAIN>` |
| Client IP filtering | (Optional) Restrict to your public IP for added security |
| TTL | Leave blank for no expiry, or set a rotation date |

Save the token value, it will not be shown again.

---

## 3. Create the API Token Secret

Fill in the token in `infra/k8s/core/cert-manager/cloudflare-api-token-secret.yaml`, then apply:

```bash
kubectl apply -f infra/k8s/core/cert-manager/cloudflare-api-token-secret.yaml
```

---

## 4. Staging: Validate the Setup

Before using the production Let's Encrypt endpoint, validate the full flow with the staging endpoint. Staging certificates are not trusted by browsers but have no rate limits, this avoids burning production quota on misconfiguration.

Apply the staging ClusterIssuer and certificate:

```bash
kubectl apply -f infra/k8s/core/cert-manager/staging/cluster-issuer-staging.yaml
kubectl apply -f infra/k8s/core/cert-manager/staging/wildcard-staging-cert.yaml
```

Monitor the certificate until it is issued:

```bash
kubectl describe certificate wildcard-staging-cert -n cert-manager
```

Look for `Status: True` and `Reason: Ready` in the `Conditions` section. This confirms that cert-manager can reach the Cloudflare API and complete the DNS-01 challenge correctly.

---

## 5. Production: Issue the Wildcard Certificate

Once staging succeeds, apply the production ClusterIssuer and certificate:

```bash
kubectl apply -f infra/k8s/core/cert-manager/prod/cluster-issuer-prod.yaml
kubectl apply -f infra/k8s/core/cert-manager/prod/wildcard-prod-cert.yaml
```

Verify issuance:

```bash
kubectl describe certificate wildcard-prod-cert -n cert-manager
```

---

## 6. Replicate the Certificate Secret with Reflector

Annotate the production certificate secret so Reflector automatically copies it to every namespace:

```bash
kubectl annotate secret wildcard-prod-tls -n cert-manager \
  reflector.v1.k8s.emberstack.com/reflection-allowed="true" \
  reflector.v1.k8s.emberstack.com/reflection-auto-enabled="true"
```

Any new namespace will automatically receive a copy of `wildcard-prod-tls`. Ingress resources in any namespace can then reference it directly.

> See [reflector.md](reflector.md) to restrict replication to specific namespaces if needed.

---

## 7. Clean Up Staging Resources

Once the production certificate is issued and verified, remove the staging resources:

```bash
kubectl delete -f infra/k8s/core/cert-manager/staging/cluster-issuer-staging.yaml
kubectl delete -f infra/k8s/core/cert-manager/staging/wildcard-staging-cert.yaml
kubectl delete secret wildcard-staging-tls -n cert-manager
```
