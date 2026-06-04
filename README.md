# infra-charts — Hub Cluster Observability Stack

GitOps-managed Helm charts for the central observability hub.
Pattern: App-of-Apps (ArgoCD) + Helm + Vault + External Secrets Operator.

## Quick Start

See [`../phase-2-hub-bootstrap.md`](../phase-2-hub-bootstrap.md) for the full step-by-step guide.

## Before You Begin

Two items need filling in before deploying:

1. **MetalLB IP pool** — edit `metallb/templates/l2-config.yaml`, replace `192.168.X.200-192.168.X.210` with your actual VM subnet range.
2. **GitHub repo URL** — replace `PLACEHOLDER` in:
   - `bootstrap/app-of-apps.yaml`
   - `argocd/applications/values.yaml`
   - `argocd/projects/values.yaml`
   - `argo-cd/values.yaml`

## Bootstrap Order

```
Step 0  talosctl apply-config  →  Talos cluster up
Step 1  helm dep update (all)  →  Chart dependencies downloaded
Step 2  helm install argo-cd   →  ArgoCD running
Step 3  kubectl apply repo-credentials secret
Step 4  helm template argocd/projects/ | kubectl apply -f -
Step 5  kubectl apply -f bootstrap/app-of-apps.yaml
Step 6  Watch ArgoCD sync waves 1-9 automatically
Step 7  vault operator init + unseal
Step 8  vault kv put (Grafana AzureAD + AlertManager secrets)
```

## Endpoints (domain: caticloud.net)

| Service | URL |
|---|---|
| Grafana | https://grafana.caticloud.net |
| ArgoCD | https://argocd.caticloud.net |
| Vault | https://vault.caticloud.net |
| Mimir | https://mimir.caticloud.net |
| Loki | https://loki.caticloud.net |
| Tempo | https://tempo.caticloud.net |
| AlertManager | https://alertmanager.caticloud.net |
| Longhorn | https://longhorn.caticloud.net |
