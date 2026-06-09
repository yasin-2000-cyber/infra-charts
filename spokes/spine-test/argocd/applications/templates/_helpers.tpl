{{/*
Standard ArgoCD Application template for spine spoke clusters.
Usage:
  {{- include "spine.app" (dict
      "name"            "alloy"
      "wave"            "4"
      "path"            "spokes/spine-test/alloy"
      "namespace"       "monitoring"
      "repoURL"         .Values.repoURL
      "targetRevision"  .Values.targetRevision
      "clusterURL"      .Values.clusterURL
  ) }}
*/}}
{{- define "spine.app" -}}
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: spine-test-{{ .name }}
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
  annotations:
    argocd.argoproj.io/sync-wave: {{ .wave | quote }}
spec:
  revisionHistoryLimit: 2
  project: spine
  source:
    repoURL: {{ .repoURL }}
    targetRevision: {{ .targetRevision }}
    path: {{ .path }}
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
