# Internal TLS Certificates (Self-Signed)

Below is how TLS certificates are issued in this homelab for internal applications - the ones served only on the internal ingress plane, under the internal zone (`*.homelab` in this setup), see [ingress-planes.md](ingress-planes.md).

Let's Encrypt cannot issue certificates for these names: the internal zone is not a public domain, so neither an HTTP-01 nor a DNS-01 challenge can prove ownership. Public applications keep using the Let's Encrypt wildcard certificate, see [cert-manager-cloudflare.md](cert-manager-cloudflare.md).

Internal certificates are issued by a cert-manager `ClusterIssuer` of type `SelfSigned`, named `selfsigned-ca`. cert-manager handles issuance and renewal; each Ingress requests its own certificate through annotations.

> Note: despite its name, `selfsigned-ca` is not a certificate authority. A `SelfSigned` issuer signs every certificate with that certificate's own key, so there is no single CA certificate to trust: browsers show a warning on every internal hostname, and each certificate has to be accepted separately. This is the current state of this homelab. Replacing it with an internal CA, whose root is trusted once on every device, is a planned improvement.

---

## 1. Prerequisites

| Requirement | Details |
|---|---|
| cert-manager installed | See [cert-manager.md](cert-manager.md) |
| Internal DNS | A Pi-hole record for each internal hostname, pointing to the load balancer - see [ingress-planes.md](ingress-planes.md), section 4 |

---

## 2. Create the ClusterIssuer

Apply [cluster-issuer-selfsigned.yaml](../../../infra/k8s/core/cert-manager/internal/cluster-issuer-selfsigned.yaml):

```bash
kubectl apply -f infra/k8s/core/cert-manager/internal/cluster-issuer-selfsigned.yaml
kubectl get clusterissuer selfsigned-ca
```

Expected output:

```
NAME            READY   AGE
selfsigned-ca   True    5s
```

A `SelfSigned` issuer has no configuration and no external dependency: it is ready immediately.

---

## 3. Request a Certificate from an Ingress

cert-manager watches Ingress resources: an Ingress annotated with `cert-manager.io/cluster-issuer` gets a `Certificate` created automatically, for the hosts and the Secret listed in its `tls` section. No separate `Certificate` manifest is needed.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: <APP-NAME>
  namespace: <NAMESPACE>
  annotations:
    cert-manager.io/cluster-issuer: selfsigned-ca
    cert-manager.io/common-name: <APP-HOSTNAME>
    cert-manager.io/duration: 8760h
    cert-manager.io/renew-before: 720h
    cert-manager.io/private-key-rotation-policy: Always
spec:
  ingressClassName: traefik
  tls:
    - hosts:
        - <APP-HOSTNAME>
      secretName: <APP-NAME>-tls
  rules:
    - host: <APP-HOSTNAME>
      ...
```

| Annotation | Value | Purpose |
|---|---|---|
| `cert-manager.io/cluster-issuer` | `selfsigned-ca` | Issuer used for this Ingress |
| `cert-manager.io/common-name` | `<APP-HOSTNAME>` | Subject CN, shown by browsers; the hostname is always in the SAN as well |
| `cert-manager.io/duration` | `8760h` | One-year validity |
| `cert-manager.io/renew-before` | `720h` | Renewal 30 days before expiry |
| `cert-manager.io/private-key-rotation-policy` | `Always` | A new private key on every renewal |

Optional subject fields can be added the same way, e.g. `cert-manager.io/subject-organizations` and `cert-manager.io/subject-countries`.

For applications installed with Helm, the same annotations go in the chart values of the Ingress (e.g. `ingress.annotations` for Gitea). Examples in this repository: [headscale/ingress.yaml](../../../infra/k8s/apps/headscale/ingress.yaml) (Headplane) and [qbittorrent/ingress.yaml](../../../infra/k8s/apps/qbittorrent/ingress.yaml).

> Note: some charts manage their own internal certificate instead. Rancher, with its default `ingress.tls.source=rancher`, creates a namespaced `Issuer` and CA of its own (see [rancher.md](rancher.md)); Harbor generates one when no certificate is provided. Leave those as the chart sets them up.

---

## 4. Verify

```bash
kubectl -n <NAMESPACE> get certificate
kubectl -n <NAMESPACE> get secret <APP-NAME>-tls -o jsonpath='{.data.tls\.crt}' | base64 -d |
  openssl x509 -noout -subject -issuer -dates -ext subjectAltName
```

Expect the certificate `READY True`, and `subject` equal to `issuer`: that is what a self-signed certificate looks like. List every certificate in the cluster with:

```bash
kubectl get certificate -A
```

---

## 5. Trusting the Certificates

Since every certificate is its own trust anchor, a client either accepts the warning per hostname in the browser, or skips verification where that is acceptable for a test (`curl -k`). Do not disable verification in application-to-application traffic: for a service that calls an internal hostname, provide that certificate explicitly instead.
