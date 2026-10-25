# Ingress NGINX to Traefik Migration

Below is how this homelab migrates from Ingress NGINX to Traefik as the cluster ingress controller, following the [official RKE2 migration guide](https://docs.rke2.io/reference/ingress_migration).

The `kubernetes/ingress-nginx` project reached end-of-life in **March 2026**: no further releases, bug fixes or security patches. RKE2 replaces it with Traefik as the default ingress controller from **v1.36**, deprecates it in the same release, and removes it entirely in **v1.37**. Since this cluster is reachable from the internet through the load balancer, the missing security patches are the reason to migrate now rather than at the forced deadline.

The migration only replaces the controller. Application manifests keep using `kind: Ingress` throughout. The controller changes in two stages: first a bridge class that lets Traefik interpret the existing `nginx.ingress.kubernetes.io/*` annotations unchanged (phases 1-4), then the native `traefik` class and its own annotation set, switched one application at a time (section 10) - the actual end state.

> Note: this migration has been executed and completed in this cluster - every application runs on the native `traefik` class, Ingress NGINX has been fully removed, and so has the bridge provider (section 10.3). This document stays as the reference for anyone repeating the same migration on another existing Ingress NGINX cluster; a fresh install should instead go straight to Traefik, see [rke2-bootstrap.md](../../rke2-bootstrap.md) ("Choose the Ingress Controller").

---

## 1. Prerequisites

| Requirement | Details |
|---|---|
| Running RKE2 cluster | See [rke2-bootstrap.md](../../rke2-bootstrap.md) |
| RKE2 `>= v1.32.11+rke2r1` | Minimum version supporting the migration - see section 2 |
| `jq` on local machine | Used by `duplicate-ingresses.sh` and `promote-ingresses.sh` |
| Cluster admin kubeconfig | See [update-kubeconfig.sh](../../../infra/k8s/bootstrap/update-kubeconfig.sh) |
| SSH access to the control plane | Configuration files live on the node filesystem |

> Note: run every `kubectl` command in this guide from a machine with a **current** admin kubeconfig - refreshed via [update-kubeconfig.sh](../../../infra/k8s/bootstrap/update-kubeconfig.sh) - not necessarily from the control plane node itself. The `~/.kube/config` copied onto the control plane by [init-rke2-cluster.sh](../../../infra/k8s/bootstrap/init-rke2-cluster.sh) is a one-time snapshot from initial bootstrap and can go stale: RKE2 client certificates are valid 12 months, and if they get rotated in place on the node (`/etc/rancher/rke2/rke2.yaml`), that local copy is not refreshed automatically. Symptom: `kubectl` fails with "the server has asked for the client to provide credentials" while another machine with a freshly-pulled kubeconfig works fine against the same cluster. Fix on the node if needed: `sudo cp /etc/rancher/rke2/rke2.yaml ~/.kube/config && sudo chown $(whoami):$(whoami) ~/.kube/config`.

Migration is supported on the following RKE2 lines:

| Line | Minimum version |
|---|---|
| v1.32 | `v1.32.11+rke2r1` |
| v1.33 | `v1.33.7+rke2r1` |
| v1.34 | `v1.34.3+rke2r1` |
| v1.35+ | Any release |

---

## 2. Upgrade RKE2

Check the current latest release per line before upgrading:

```bash
curl -s https://update.rke2.io/v1-release/channels |
  jq -r '.data[] | select(.latest) | "\(.id)\t\(.latest)"'
```

> Note: the channel API can advertise a release whose artifacts were never published or were pulled - `v1.32.13+rke2r2` is one such case, and the installer fails with a 404 on `sha256sum-amd64.txt`. Confirm the target version actually has assets before running the installer:
>
> ```bash
> curl -s "https://api.github.com/repos/rancher/rke2/releases/tags/${VERSION//+/%2B}" |
>   jq '{tag: .tag_name, assets: (.assets | length)}'
> ```
>
> An `assets` count of `0` means the release is unusable: fall back to the previous one.

On the control plane:

```bash
curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_VERSION="v1.32.13+rke2r1" sh -
sudo systemctl restart rke2-server
```

Then on each worker, one at a time. `INSTALL_RKE2_TYPE="agent"` is required: without it the installer defaults to `server` and lays down control plane systemd units on a worker node.

```bash
curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_VERSION="v1.32.13+rke2r1" INSTALL_RKE2_TYPE="agent" sh -
sudo systemctl restart rke2-agent
```

> Note: the `kubectl` symlink created by [init-rke2-cluster.sh](../../../infra/k8s/bootstrap/init-rke2-cluster.sh) points inside `/var/lib/rancher/rke2/data/<hash>/bin/`, and that directory changes on every upgrade. Recreate it on the control plane after restarting:
>
> ```bash
> sudo ln -sf $(find /var/lib/rancher/rke2/data/ -name kubectl | head -1) /usr/local/bin/kubectl
> ```

Verify every node reports the new version before continuing:

```bash
kubectl get nodes -o wide
```

---

## 3. Annotation Compatibility

Traefik's `kubernetesIngressNGINX` provider interprets NGINX annotations, but not all of them are supported. Every annotation currently used in this repository is covered:

| Annotation | Used by | Supported | Notes |
|---|---|---|---|
| `ssl-redirect` | all apps | Yes | Cannot be opted out per route once enabled globally |
| `proxy-body-size` | gokapi | Yes | |
| `proxy-read-timeout` | gokapi | Yes | Can also be set globally at provider level |
| `proxy-send-timeout` | gokapi | Yes | Can also be set globally at provider level |
| `proxy-connect-timeout` | gokapi | Yes | Can also be set globally at provider level |
| `proxy-buffering` | gokapi | Yes | |
| `proxy-request-buffering` | gokapi | Yes | NGINX buffers by default, Traefik requires explicit opt-in |

To re-check after adding new applications, run the [Traefik Ingress NGINX Annotations Discovery Tool](https://github.com/traefik/ingress-nginx-migration) against the live cluster, and consult the [annotation support reference](https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/ingress-nginx/#annotations-support).

> Note: gokapi is the application to validate first. It is the only one relying on buffering and body-size behaviour, which is exactly where NGINX and Traefik defaults differ.

> Note: "Supported" here means the bridge provider (phases 1-4) correctly interprets the annotation - it does not mean the annotation is still needed once converted to the native class. Section 10.1 covers that later, separate step, and reaches the opposite conclusion for most of these: drop them, native Traefik does not need an equivalent.

---

## 4. Phase 1 - Run Both Controllers

### 4.1 Pin the ingress class on every Ingress

With two controllers active, an Ingress without an explicit class is contended by both. Pin everything to `nginx` first:

```bash
./infra/k8s/core/ingress-migration/patch-ingress-class.sh
```

The manifests under `infra/k8s/apps/*/ingress.yaml` declared `ingressClassName: nginx` at this stage of the migration - true for this repository when phase 1 began, no longer true today, since those files have since been updated to reflect the post-migration end state (section 10). On a cluster starting this migration fresh, confirm the equivalent manifests actually start on `nginx` before relying on this claim; either way, this script's main purpose is to catch resources created outside the repository - in particular the Rancher Ingress in `cattle-system` (see section 8).

### 4.2 Enable Traefik alongside Ingress NGINX

On the control plane node, merge the contents of [phase1-config.yaml](../../../infra/k8s/core/ingress-migration/phase1-config.yaml) into `/etc/rancher/rke2/config.yaml`:

```yaml
ingress-controller:
  - ingress-nginx
  - traefik
```

### 4.3 Bind Traefik to temporary ports

Copy [phase1-rke2-traefik-config.yaml](../../../infra/k8s/core/ingress-migration/phase1-rke2-traefik-config.yaml) to the control plane as `/var/lib/rancher/rke2/server/manifests/rke2-traefik-config.yaml`.

It does two things: binds Traefik to host ports `8000`/`8443` so Ingress NGINX keeps `80`/`443`, and enables the NGINX compatibility provider bound to a dedicated ingress class.

| Setting | Value |
|---|---|
| Traefik HTTP host port | `8000` |
| Traefik HTTPS host port | `8443` |
| Bridge ingress class | `rke2-ingress-nginx-migration` |
| Controller class | `rke2.cattle.io/ingress-nginx-migration` |

> Note: the provider key was renamed to `kubernetesIngressNGINX` in the June 2026 releases (`v1.36.2+`, `v1.35.6+`, `v1.34.9+`, `v1.33.13+`); before that it is spelled `kubernetesIngressNginx` (lowercase "nginx"). The v1.32 line is **not** listed among the renamed releases, so on this cluster the lowercase spelling is the likely one. A wrong key is silently ignored and the provider never starts, so confirm it with the log check in section 4.4: if the `ingressnginx.Provider` line does not appear, switch the spelling and restart `rke2-server`.

### 4.4 Restart and verify

```bash
sudo systemctl restart rke2-server
```

```bash
kubectl get daemonset -n kube-system
kubectl get ingressclass
kubectl logs -n kube-system -l app.kubernetes.io/name=rke2-traefik | grep -i "ingressnginx"
```

| Check | Expected |
|---|---|
| DaemonSets | Both `rke2-ingress-nginx-controller` and `rke2-traefik` running |
| IngressClass | `rke2-ingress-nginx-migration` present |
| Traefik logs | `Starting provider *ingressnginx.Provider` |

---

## 5. Phase 2 - Validate in Parallel

### 5.1 Duplicate the Ingress resources

```bash
./infra/k8s/core/ingress-migration/duplicate-ingresses.sh
```

Each nginx-class Ingress is copied with a `-traefik` suffix and reclassified to `rke2-ingress-nginx-migration`. Production traffic is unaffected: the originals keep serving on `80`/`443`.

### 5.2 Test each application through Traefik

Real DNS for each hostname does not point at a worker node - it resolves to the load balancer or straight to the public IP, and neither reaches Traefik's temporary host port `8443` on the nodes. Following the real hostname as-is would never reach Traefik at all. Two ways to point the request at a worker node directly instead, both sending the correct `Host` header and TLS SNI so Traefik can still match the right router:

For a one-off check with `curl`, override resolution for just that command - nothing to clean up afterwards:

```bash
curl -kv --resolve <APP-HOSTNAME>.<YOUR-DOMAIN>:8443:<worker-ip> https://<APP-HOSTNAME>.<YOUR-DOMAIN>:8443/
```

For testing in a browser (playback, login flows), add a temporary `/etc/hosts` entry pointing the hostname at a worker node instead, and remove it once done:

```
<worker-ip>  <APP-HOSTNAME>.<YOUR-DOMAIN>
```

| Application | What to verify |
|---|---|
| gokapi | Upload of a large file - covers `proxy-body-size`, buffering and timeouts |
| jellyfin | Video playback - covers long-lived streaming connections |
| qbittorrent | Web UI login and session persistence |
| headscale | Both path prefixes: `/` (headscale) and `/admin` (headplane) |

Also confirm TLS is served from the `wildcard-prod-tls` secret in each namespace, replicated by [Reflector](reflector.md).

> Note: this phase can stay in place as long as needed. Nothing is switched over until phase 3, and the temporary ports are not exposed through the load balancer.

### 5.3 Known conflict: wildcard catch-all vs exact-host routing

If the cluster has a wildcard Ingress acting as a catch-all (e.g. `host: '*.example.com'` routing to a default 404 backend, used to serve a friendly error page for undefined subdomains), it will silently swallow every other Ingress under the same wildcard once duplicated onto the `rke2-ingress-nginx-migration` class.

**Symptom:** every app under the wildcard domain returns `404` through Traefik (port `8443`), even though each has its own correct, specific-host Ingress. The response's `server` header identifies the catch-all's own backend as the one that answered, not the target application.

**Cause:** NGINX resolves `server_name` matches by specificity - an exact host always wins over a wildcard, regardless of Ingress creation order or resource size. Traefik has no such logic: its default router priority is the **character length of the compiled rule**, and a wildcard host compiles to a `HostRegexp` expression that is frequently longer (and therefore higher priority) than a plain `Host()` match. The `kubernetesIngressNGINX` compatibility provider does not support any priority-related annotation - confirmed against the [provider's annotation reference](https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/ingress-nginx/) - so `nginx.ingress.kubernetes.io/*` annotations cannot fix this, and the native `traefik.ingress.kubernetes.io/router.priority` annotation is silently ignored on Ingresses using the bridge class.

**Fix:** move only the wildcard catch-all Ingress to the native `traefik` ingress class - not the migration bridge class - where `router.priority` is honored, and give it an explicitly low priority so any specific-host Ingress outranks it:

```bash
kubectl patch ingress <catch-all-name>-traefik -n <namespace> \
  --type=merge -p '{"spec":{"ingressClassName":"traefik"}}'

kubectl annotate ingress <catch-all-name>-traefik -n <namespace> \
  traefik.ingress.kubernetes.io/router.priority="1" --overwrite
```

Verify the fix does not overcorrect: a genuinely undefined subdomain under the wildcard must still return the catch-all's `404`, while every defined app now reaches its own backend.

> Note: this Ingress no longer follows the rest of the cleanup pattern in phase 4 - it is already on its final class (`traefik`, not `rke2-ingress-nginx-migration`) and needs no further change at switchover.

### 5.4 Known issue: headless Services used for external endpoints

This cluster exposes apps running outside Kubernetes (Pi-hole, Proxmox, the TrueNAS SMB share) through a recurring pattern: a selectorless Service with manually-managed `Endpoints`, so an Ingress backend - or, for the SMB share, the CSI driver - can point at an external IP. These Services were all defined as **headless** (`clusterIP: None`).

**Symptom:** every one of these apps returns `503` through Traefik (port `8443`), while the exact same Service and Ingress serve correctly through Ingress NGINX on `80`/`443`.

**Cause:** Traefik has a known, unresolved limitation with headless Services backed by manually-managed Endpoints - confirmed against [multiple open issues](https://community.traefik.io/t/traefik-returns-503-no-available-server-when-routing-to-external-ip-via-headless-service/27430) spanning several Traefik versions. It returns "503 no available server" even though the EndpointSlice is correctly populated and marked ready. Ingress NGINX has no such issue: it builds its upstream list directly from the Endpoints/EndpointSlice addresses regardless of whether the Service is headless.

**Fix, part 1:** replace `clusterIP: None` with a normal (non-headless) ClusterIP, keeping the Service selectorless and the same manually-managed Endpoints. This is a standard, fully supported Kubernetes pattern and resolved the `503` in testing.

**Fix, part 2 (the real trap):** removing `clusterIP: None` makes kube-proxy responsible for programming ClusterIP routing for this Service for the first time - and that routing silently fails if the Service's port and the Endpoints' port don't have the **same `name`**. A headless Service gets no kube-proxy ClusterIP rules at all, so a name mismatch between `Service.spec.ports[].name` and `Endpoints.subsets[].ports[].name` is completely harmless there. Once non-headless, kube-proxy cannot correlate an unnamed (or differently-named) ServicePort to a named EndpointPort, and the ClusterIP ends up with **no working route to it at all** - not a Traefik-specific error, `connection refused` from any pod, confirmed with a plain `wget` against the ClusterIP with no Ingress involved.

Symptom recap if only part 1 is applied: the Service gets a real ClusterIP, `kubectl get endpoints` looks entirely correct, but every request still fails - `connection refused` at the TCP level rather than the original `503`.

```bash
kubectl get svc <name> -n <namespace> -o jsonpath='{.spec.ports}'
kubectl get endpoints <name> -n <namespace> -o jsonpath='{.subsets[0].ports}'
# the "name" field must match (or both be absent) between the two
```

Both fixes are applied to [smb-server-service.yaml](../../../infra/k8s/core/storage/smb-csi/smb-server-service.yaml) in this repository; apply the same changes to every other Service that follows this pattern. Applying either fix requires deleting and recreating the Service - `clusterIP` is immutable - which also deletes the manually-managed `Endpoints` object if it was created without care: recreate the Service and the Endpoints together, in the same pass, rather than assuming the Endpoints will survive.

---

## 6. Phase 3 - Switch Over

### 6.1 Remove Ingress NGINX

On the control plane, replace the `ingress-controller` block in `/etc/rancher/rke2/config.yaml` with [phase3-config.yaml](../../../infra/k8s/core/ingress-migration/phase3-config.yaml):

```yaml
ingress-controller:
  - traefik
```

### 6.2 Move Traefik to the standard ports

Replace `/var/lib/rancher/rke2/server/manifests/rke2-traefik-config.yaml` with [phase3-rke2-traefik-config.yaml](../../../infra/k8s/core/ingress-migration/phase3-rke2-traefik-config.yaml). The `ports` block is dropped, so Traefik falls back to `80`/`443`.

### 6.3 Restart and verify

```bash
sudo systemctl restart rke2-server
```

```bash
kubectl get daemonset -n kube-system
kubectl get pods -n kube-system -l app.kubernetes.io/name=rke2-traefik -o wide
```

Then verify each application through its public hostname, without the port override and without the `/etc/hosts` entry.

> Note: the Ingress NGINX DaemonSet can take several minutes to disappear because of admission webhook teardown. Wait for it to be fully gone before declaring the switchover complete.

No load balancer change is required. The load balancer forwarded TCP to the nodes on `443` and used passive health checks (`max_fails` / `fail_timeout`), so there was no HTTP probe path to update from `/healthz` to `/ping`.

---

## 7. Phase 4 - Cleanup

Once every application is confirmed working on `80`/`443` - and, if following section 10, already converted to the native `traefik` class - two things are left, in this order.

**7.1 Delete the legacy nginx-class originals.** This frees up the plain resource names, still held by the dead originals:

```bash
./infra/k8s/core/ingress-migration/delete-legacy-ingresses.sh
```

**7.2 Promote the `-traefik` duplicates to their final name.** Kubernetes has no rename operation - this creates a copy under the final name (same spec, same class and annotations) and deletes the `-traefik` original:

```bash
./infra/k8s/core/ingress-migration/promote-ingresses.sh
```

Finally, reconcile the repository with the cluster: `infra/k8s/apps/*/ingress.yaml` should already match this end state if section 10 was followed - `ingressClassName: traefik`, no `-traefik` suffix, no leftover `nginx.ingress.kubernetes.io/*` annotations - so a fresh `kubectl apply` reproduces the running state.

> Note: running phase 4 without first converting to the native class (section 10) is also valid - the `-traefik` duplicates get promoted as-is, still on the bridge class. That end state routes through the NGINX compatibility provider, which is transitional by design: moving to native Traefik configuration, or to Gateway API, remains a separate change to do afterwards.

---

## 8. Rancher

The RKE2 guide warns that clusters running Rancher need special handling for the Rancher Ingress, and this cluster runs Rancher (see [rancher.md](rancher.md)).

The Rancher Ingress in `cattle-system` is managed by its Helm chart, not by the manifests in this repository. Two consequences:

- The class patch in section 4.1 and the duplication in section 5.1 apply to it as well, but a `helm upgrade` of the Rancher chart can revert the change.
- Migrate Rancher **last**, after all other applications are confirmed on Traefik, so the cluster management UI stays reachable throughout the migration.

If the Rancher Ingress misbehaves under Traefik, the fastest recovery is to restore its original nginx-class definition while Ingress NGINX is still running - which is why validating Rancher on the bridge class must be handled before phase 3, not after.

The rest of this section is a separate, later step: converting Rancher from the bridge class to the native `traefik` class, same as section 10 for every other application - done well after phase 3, once Ingress NGINX is already gone.

### 8.1 Converting Rancher to the native class

The Rancher chart exposes the ingress class as a value, not something to patch on the live Ingress: `ingress.ingressClassName`. Apply it with `--reuse-values` so nothing else changes:

```bash
helm upgrade rancher rancher-stable/rancher \
  --namespace cattle-system \
  --reuse-values \
  --set ingress.ingressClassName=traefik
```

> Note: pin `--version` to whatever is currently deployed (`helm list -n cattle-system`). Without it, `helm upgrade` resolves to the latest chart in the local repo cache, which can be several minor versions ahead and introduce unrelated breaking changes - a jump from 2.12.3 to 2.15.2 failed outright here on a `nil pointer evaluating interface {}.gatewayClass`, from a Gateway API values structure the older release never had. Upgrading the Rancher app itself is a separate decision, not a side effect of changing its Ingress class.

The chart also injects `nginx.ingress.kubernetes.io/proxy-*-timeout` annotations on its own, regardless of values - they stay present after the switch but become inert, the same way gokapi's did: Traefik's own backend-facing defaults are already more generous.

By this point in the migration Ingress NGINX itself no longer exists in the cluster (removed in phase 3), so the rollback path from section 8 no longer applies as written - there is no nginx class to restore. The equivalent safety net is the bridge class instead, as long as the bridge provider is still enabled (until section 10.3):

```bash
helm upgrade rancher rancher-stable/rancher \
  --namespace cattle-system \
  --version <currently-deployed-version> \
  --reuse-values \
  --set ingress.ingressClassName=rke2-ingress-nginx-migration
```

---

## 9. Rollback

Each phase is reversible while Ingress NGINX is still installed, that is, at any point before phase 3.

| Phase | Rollback |
|---|---|
| 1 | Remove `traefik` from `ingress-controller` in `config.yaml`, delete `rke2-traefik-config.yaml`, restart `rke2-server` |
| 2 | Delete the `-traefik` duplicates, then roll back phase 1 |
| 3 | Restore the phase 1 configuration files and restart - Ingress NGINX is reinstalled by the Helm controller |
| 4 | Not reversible: the legacy nginx-class resources are gone, and Ingress NGINX itself was already removed in phase 3, so recreating them would not route anything regardless. If only 7.1 ran, the `-traefik` duplicates are still live and untouched - nothing else to roll back. `infra/k8s/apps/*/ingress.yaml` reflects the current end state (native `traefik` class, if section 10 was followed), not an earlier one - it cannot be used to restore a prior step |

---

## 10. After the Migration

The bridge class (`rke2-ingress-nginx-migration`) created in phase 1 is transitional, not a destination - it exists only to let legacy `nginx.ingress.kubernetes.io/*` annotations keep working during the migration. It is also cluster-specific: a fresh RKE2 install that was never run through phase 1 does not have this IngressClass at all, so manifests pinned to it would silently match no controller. Once every application is confirmed stable on the bridge class, convert each Ingress to the native `traefik` class, dropping or rewriting annotations that have a native Traefik equivalent (see the [annotation support reference](https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/ingress-nginx/#annotations-support)) - this is the actual end state, and the one a fresh install should match directly.

### 10.1 Annotation conversion pattern

Not to be confused with section 3: that table covers the bridge provider during phases 1-4 (annotations still work, unchanged); this one covers the native class, the end state. There is no per-app recipe here on purpose - this is the pattern validated across every application in this cluster, not an app-by-app checklist. Apply it to whatever `nginx.ingress.kubernetes.io/*` annotations a given Ingress actually carries:

| NGINX annotation | Native handling |
|---|---|
| `ssl-redirect` | Drop. Configure once, globally, at the Traefik entrypoint (`ports.web.http.redirections.entryPoint`) rather than per Ingress - there is no per-router opt-out once set, see the note in `phase3-rke2-traefik-config.yaml` |
| `proxy-body-size` | Drop. Traefik has no default request body size limit to raise |
| `proxy-buffering` / `proxy-request-buffering` | Drop. Traefik never buffers by default, unlike NGINX |
| `proxy-connect-timeout` / `proxy-read-timeout` / `proxy-send-timeout` | Drop. These control the Traefik-to-backend leg; Traefik's own `ServersTransport` defaults there are already generous (`dialTimeout: 30s`, `responseHeaderTimeout: 0s`/unlimited) |
| `rewrite-target` | Verify empirically before assuming it does anything: NGINX only rewrites the matched capture group, and a plain `path: /` with no regex has none. Compare two different paths' responses - if they differ, it was already a no-op and can be dropped |
| `backend-protocol: HTTPS` (self-signed backend) | No Ingress-level equivalent. Needs a `ServersTransport` resource (`insecureSkipVerify: true`) plus two annotations on the backend **Service** (not the Ingress): `traefik.ingress.kubernetes.io/service.serversscheme: https` and `traefik.ingress.kubernetes.io/service.serverstransport: <namespace>-<name>@kubernetescrd` |
| `backend-protocol: HTTP` | Drop. Traefik's own default scheme to a backend |

The one gap that is not an NGINX annotation at all: Traefik's entrypoint `transport.respondingTimeouts.readTimeout` defaults to 60s (client-facing, unlike the backend-facing timeouts above) and has no per-Ingress override - raise it globally if any application does large or slow uploads (see `phase3-rke2-traefik-config.yaml`).

### 10.2 Helm-managed apps (Rancher, Gitea, Harbor in this cluster)

Two traps specific to apps whose Ingress is owned by a Helm chart rather than a plain manifest, found converting all three in this cluster:

**The phase-2 duplicate silently goes stale.** `duplicate-ingresses.sh` creates the `-traefik` copy as a Kubernetes object completely separate from the one Helm tracks. A later `helm upgrade` only updates the Helm-owned original - the duplicate stays frozen on the bridge class forever, and once the original is converted to the native class, both objects route the exact same host simultaneously under two different providers. Delete the stale duplicate as soon as the original is confirmed converted, rather than waiting for phase 4 cleanup:

```bash
kubectl delete ingress <app>-traefik -n <namespace>
```

**`helm upgrade` can conflict with phase 1's own patch.** `patch-ingress-class.sh` used `kubectl patch`, which registers field ownership under a manager named `kubectl-patch`. If a chart's template later tries to set that same field (`.spec.ingressClassName`) via Helm's Server-Side Apply, the upgrade fails outright: `Apply failed with 1 conflict: conflict with "kubectl-patch" ... .spec.ingressClassName`. Simplest fix: write the field directly with the same mechanism that already owns it, instead of fighting the conflict through Helm:

```bash
kubectl patch ingress <app> -n <namespace> --type=merge -p '{"spec":{"ingressClassName":"traefik"}}'
```

Also check the actual values key with `helm show values <chart> --version <version>` rather than assume it - it is not consistent across charts: `ingress.ingressClassName` for Rancher, `ingress.className` for Gitea, `expose.ingress.className` for Harbor.

### 10.3 Disable the bridge provider

The last step of the migration. The phase 3 configuration still enables the NGINX compatibility provider, because the migrated Ingresses were on the bridge class at that point. Once every Ingress is on the native `traefik` class, the provider has nothing left to serve - but it keeps watching for Ingresses of the bridge class, so any object still, or newly, pinned to it (an old manifest, a chart default) would be served with NGINX annotation semantics instead of failing visibly. Turn it off.

**1. Confirm nothing uses the bridge class:**

```bash
kubectl get ingress -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,CLASS:.spec.ingressClassName' | grep -v ' traefik$'
```

Expect only the header line.

**2. Back up and edit the configuration.** On the control plane:

```bash
sudo cp /var/lib/rancher/rke2/server/manifests/rke2-traefik-config.yaml ~/rke2-traefik-config.yaml.bak-provider
sudoedit /var/lib/rancher/rke2/server/manifests/rke2-traefik-config.yaml
```

Remove the whole `providers` block, spelled as in phase 1 (see the note in section 4.3):

```yaml
    providers:
      kubernetesIngressNginx:
        enabled: true
        ingressClass: "rke2-ingress-nginx-migration"
        controllerClass: "rke2.cattle.io/ingress-nginx-migration"
```

Nothing replaces it: the chart default is `enabled: false`. The chart also creates the `rke2-ingress-nginx-migration` IngressClass only while the provider is enabled, so Helm deletes the class in the same step. RKE2 applies the change automatically and the Traefik DaemonSet rolls one node at a time.

> Note: if the cluster has moved on to another configuration since phase 3 - as this one has, see [ingress-planes.md](ingress-planes.md) - edit the file currently installed, not `phase3-rke2-traefik-config.yaml`. The configuration this cluster runs after this step is [rke2-traefik-config.yaml](../../../infra/k8s/core/traefik/rke2-traefik-config.yaml).

**3. Verify:**

```bash
kubectl -n kube-system rollout status daemonset/rke2-traefik
kubectl -n kube-system get daemonset rke2-traefik -o jsonpath='{.spec.template.spec.containers[0].args}' | tr ',' '\n' | grep -ci kubernetesingressnginx
kubectl get ingressclass
```

Expect `0` from the second command, and only the `traefik` IngressClass. Then check every application through its hostname: routing does not change, since no Ingress used the provider.

**Rollback:** restore `~/rke2-traefik-config.yaml.bak-provider` to the manifests directory. The provider and the IngressClass come back with the next rollout.
