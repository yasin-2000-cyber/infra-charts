# infra-charts — Unified Multi-K8s Observability Platform (Hub)

GitOps-managed Helm charts for the central observability hub cluster.
Pattern: **ArgoCD App-of-Apps** → **Helm** → **Vault + External Secrets Operator**.

> **Repo:** `https://github.com/yasin-2000-cyber/infra-charts.git` (public — zero secrets in git)

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                  HUB CLUSTER (Talos)                │
│  Grafana · Mimir · Loki · Tempo · AlertManager      │
│  ArgoCD · Vault · External Secrets Operator         │
│  MetalLB · NGINX Ingress · cert-manager             │
│  Longhorn (distributed block storage)               │
└──────────────┬────────────────────────┬─────────────┘
               │   push (OTLP / remote_write / HTTPS)
    ┌──────────▼────────────┐   ┌───────▼───────────────┐
    │  SPOKE: Talos DC      │   │  SPOKE: Kubeadm DC    │  ...
    │  Grafana Alloy        │   │  Grafana Alloy        │
    │  OTel Operator        │   │  OTel Operator        │
    └───────────────────────┘   └───────────────────────┘
```

- All data flows **push spoke → hub** (no hub-to-spoke connections)
- Each spoke = one Loki/Mimir/Tempo tenant via `X-Scope-OrgID`
- SSO via **Microsoft Azure AD** (`[auth.azuread]` in Grafana — no Keycloak)

---

## Hub Node Specs

| Node | Hostname | IP | Role | RAM | vCPU | Storage |
|---|---|---|---|---|---|---|
| master | k8sm01-test | 100.64.5.51 | control-plane only | 4 GB | 4 | 20 GB OS |
| worker-1 | k8sw01-test | 100.64.5.52 | workloads | 8 GB | 8 | 20 GB OS + 75 GB Longhorn |
| worker-2 | k8sw02-test | 100.64.5.53 | workloads | 8 GB | 8 | 20 GB OS + 75 GB Longhorn |

**MetalLB L2 pool:** `100.65.5.70 – 100.65.5.79`

---

## Directory Structure

```
infra-charts/
├── talos/patches/              # Talos machine config patches (apply before ArgoCD)
│   ├── controlplane-patch.yaml
│   └── worker-patch.yaml
│
├── bootstrap/
│   └── app-of-apps.yaml        # Single kubectl apply — starts everything
│
├── argo-cd/                    # ArgoCD wrapper (one-time helm install, then self-managed)
├── argocd/
│   ├── applications/           # Helm chart that generates all ArgoCD Application CRDs
│   │   └── templates/hub/      # One .yaml per component (wave-ordered)
│   └── projects/               # AppProject: hub
│
├── metallb/                    # Wave 1 — L2 LoadBalancer
├── ingress-nginx/              # Wave 2 — Ingress controller
├── cert-manager/               # Wave 3 — TLS (selfsigned + CA + Let's Encrypt)
├── trust-manager/              # Wave 4 — CA bundle distribution
├── longhorn/                   # Wave 4 — Distributed block storage
├── vault/                      # Wave 5 — Secret store
├── external-secrets/           # Wave 6 — Vault → K8s Secret sync
├── mimir/                      # Wave 7 — Metrics hub
├── loki/                       # Wave 8 — Log hub
├── tempo/                      # Wave 8 — Trace hub
├── grafana/                    # Wave 9 — Visualization + SSO
└── alertmanager/               # Wave 9 — Alert routing
```

---

## Sync Wave Order

| Wave | Component(s) | Namespace(s) |
|---|---|---|
| 1 | argocd-projects, metallb | argocd, metallb-system |
| 2 | argo-cd (self), ingress-nginx | argocd, ingress-nginx |
| 3 | cert-manager | cert-manager |
| 4 | trust-manager, longhorn | cert-manager, longhorn-system |
| 5 | vault | vault |
| 6 | external-secrets | external-secrets |
| 7 | mimir | monitoring |
| 8 | loki, tempo | monitoring |
| 9 | grafana, alertmanager | monitoring |

---

## Bootstrap Steps

Full details: [`../phase-2-hub-bootstrap.md`](../phase-2-hub-bootstrap.md)

```bash
# 0. Apply Talos machine configs (before cluster bootstrap)
talosctl apply-config --nodes 100.64.5.51 --file talos/generated/patched-controlplane.yaml
talosctl apply-config --nodes 100.64.5.52 --file talos/generated/patched-worker.yaml
talosctl apply-config --nodes 100.64.5.53 --file talos/generated/patched-worker.yaml
talosctl bootstrap --nodes 100.64.5.51
talosctl kubeconfig --nodes 100.64.5.51

# 1. Download Helm dependencies (run once per chart)
for dir in argo-cd metallb ingress-nginx cert-manager trust-manager longhorn \
           vault external-secrets mimir loki tempo grafana alertmanager; do
  helm dep update $dir/
done

# 2. Install ArgoCD (one-time bootstrap)
helm install argo-cd argo-cd/ -n argocd --create-namespace

# 3. Create ArgoCD repo credentials secret
kubectl create secret generic repo-credentials -n argocd \
  --from-literal=username=<github-username> \
  --from-literal=password=<github-pat>
kubectl label secret repo-credentials -n argocd \
  argocd.argoproj.io/secret-type=repository

# 4. Bootstrap AppProject
helm template argocd/projects/ | kubectl apply -f -

# 5. Apply App-of-Apps (ArgoCD takes over from here)
kubectl apply -f bootstrap/app-of-apps.yaml

# 6. After wave 5 — Initialize and unseal Vault
kubectl exec -n vault vault-0 -- vault operator init \
  -key-shares=5 -key-threshold=3 -format=json > vault-init-output.json  # store securely!
kubectl exec -n vault vault-0 -- vault operator unseal <KEY_1>
kubectl exec -n vault vault-0 -- vault operator unseal <KEY_2>
kubectl exec -n vault vault-0 -- vault operator unseal <KEY_3>

# Create the token secret that vault-init-job.yaml reads
kubectl create secret generic vault-init-token -n vault \
  --from-literal=token=<ROOT_TOKEN_FROM_INIT_OUTPUT>

# 7. After wave 6 — Populate Vault secrets (required by ExternalSecrets)
export VAULT_ADDR=https://vault.caticloud.net
export VAULT_TOKEN=<ROOT_TOKEN>

vault kv put secret/hub/prod/grafana-azuread \
  AZURE_CLIENT_ID="<app-client-id>" \
  AZURE_CLIENT_SECRET="<app-client-secret>" \
  AZURE_TENANT_ID="<tenant-id>"

vault kv put secret/hub/prod/alertmanager \
  SLACK_WEBHOOK_URL="https://hooks.slack.com/services/..." \
  SMTP_PASSWORD="<smtp-app-password>"

# 8. Before wave 9 — Create Grafana admin secret (NOT in git)
kubectl create secret generic grafana-admin-secret -n monitoring \
  --from-literal=admin-user=admin \
  --from-literal=admin-password=<strong-password>
```

---

## Secrets — What Lives Where

| Secret | Location | Method |
|---|---|---|
| Vault root token / unseal keys | `vault-init-output.json` (local only, gitignored) | Manual `vault operator init` |
| `vault-init-token` K8s secret | vault namespace | Manual `kubectl create secret` |
| Azure AD client ID/secret/tenant | Vault `secret/hub/prod/grafana-azuread` | ExternalSecret → `grafana-azuread-secret` |
| AlertManager Slack/SMTP creds | Vault `secret/hub/prod/alertmanager` | ExternalSecret → `alertmanager-credentials` |
| Grafana admin password | monitoring namespace | Manual `kubectl create secret` (`grafana-admin-secret`) |
| ArgoCD repo PAT | argocd namespace | Manual `kubectl create secret` (`repo-credentials`) |
| Talos cluster secrets | `talos/generated/` (local only, gitignored) | `talosctl gen config` |

**Zero secrets are stored in git.** All runtime credentials flow through Vault → External Secrets Operator → K8s Secrets.

---

## Endpoints

| Service | URL | TLS |
|---|---|---|
| Grafana | https://grafana.caticloud.net | Let's Encrypt |
| ArgoCD | https://argocd.caticloud.net | Let's Encrypt |
| Vault | https://vault.caticloud.net | Internal CA |
| Longhorn | https://longhorn.caticloud.net | Internal CA |
| Mimir (remote_write) | https://mimir.caticloud.net | Let's Encrypt |
| Loki (log push) | https://loki.caticloud.net | Let's Encrypt |
| Tempo (OTLP) | https://tempo.caticloud.net | Let's Encrypt |
| AlertManager | https://alertmanager.caticloud.net | Let's Encrypt |

---

## Helm Chart Versions

| Chart | Version |
|---|---|
| argo-cd | 8.2.7 |
| metallb | 0.14.9 |
| ingress-nginx | 4.11.3 |
| cert-manager | v1.17.2 |
| trust-manager | v0.22.1 |
| longhorn | 1.7.2 |
| vault | 0.32.0 |
| external-secrets | 0.10.7 |
| mimir-distributed | 5.5.0 |
| loki | 6.6.2 |
| tempo | 1.10.3 |
| grafana | 8.4.6 |
| alertmanager | 1.13.0 |

---

## Post-Deploy Verification

```bash
# All pods healthy
kubectl get pods -A | grep -v Running | grep -v Completed

# All ArgoCD apps synced
kubectl get applications -n argocd

# Backend health checks
curl -k https://mimir.caticloud.net/ready
curl -k https://loki.caticloud.net/ready
curl -k https://tempo.caticloud.net/ready

# Grafana loads with "Sign in with Microsoft" button
open https://grafana.caticloud.net

# Vault unsealed
vault status
```
