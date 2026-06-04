{{/*
Standard ArgoCD Application template.
Usage:
  {{- include "app.standard" (dict
      "name"            "loki"
      "wave"            "8"
      "path"            "loki"
      "namespace"       "monitoring"
      "repoURL"         .Values.repoURL
      "targetRevision"  .Values.targetRevision
      "clusterURL"      .Values.clusterURL
  ) }}
*/}}
{{- define "app.standard" -}}
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: {{ .name }}
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
  annotations:
    argocd.argoproj.io/sync-wave: {{ .wave | quote }}
spec:
  project: hub
  source:
    repoURL: {{ .repoURL }}
    targetRevision: {{ .targetRevision }}
    path: infra-charts/{{ .path }}
    helm:
      releaseName: {{ .name }}
  destination:
    server: {{ .clusterURL }}
    namespace: {{ .namespace }}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
{{- end -}}
