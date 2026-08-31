# ── Observability Stack — OTel + VictoriaMetrics + VictoriaLogs + Tempo + Grafana ──

OBS_DIR := justfile_directory() + "/infra/k8s/observability"

# Install VictoriaMetrics single-node (metrics backend, Prometheus-compatible)
obs-victoria-metrics:
	#!/usr/bin/env bash
	set -euo pipefail
	helm repo add victoriametrics https://victoriametrics.github.io/helm-charts/ 2>/dev/null || true
	helm repo update victoriametrics
	helm upgrade --install victoria-metrics-single victoriametrics/victoria-metrics-single \
	  --namespace monitoring --create-namespace \
	  --wait --timeout 5m \
	  -f "{{OBS_DIR}}/victoria-metrics/values.yaml"
	echo "VictoriaMetrics ready. Remote write: http://victoria-metrics-single-server.monitoring.svc.cluster.local:8428/api/v1/write"

# Install VictoriaLogs single-node (log backend, OTLP + Loki-compatible API)
obs-victoria-logs:
	#!/usr/bin/env bash
	set -euo pipefail
	helm repo add victoriametrics https://victoriametrics.github.io/helm-charts/ 2>/dev/null || true
	helm repo update victoriametrics
	helm upgrade --install victoria-logs-single victoriametrics/victoria-logs-single \
	  --namespace monitoring --create-namespace \
	  --wait --timeout 5m \
	  -f "{{OBS_DIR}}/victoria-logs/values.yaml"
	echo "VictoriaLogs ready. OTLP: http://victoria-logs-single-server.monitoring.svc.cluster.local:9428/insert/opentelemetry"

# Install Grafana Tempo (trace backend, OTLP receiver)
obs-tempo:
	#!/usr/bin/env bash
	set -euo pipefail
	helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
	helm repo update grafana
	helm upgrade --install tempo grafana/tempo \
	  --namespace monitoring --create-namespace \
	  --wait --timeout 5m \
	  -f "{{OBS_DIR}}/tempo/values.yaml"
	echo "Tempo ready. OTLP gRPC: tempo.monitoring.svc.cluster.local:4317"

# Install OpenTelemetry Collector DaemonSet (scrapes + collects + forwards everything)
obs-otel-collector:
	#!/usr/bin/env bash
	set -euo pipefail
	helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts 2>/dev/null || true
	helm repo update open-telemetry
	helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
	  --namespace monitoring --create-namespace \
	  --wait --timeout 5m \
	  -f "{{OBS_DIR}}/otel-collector/values.yaml"
	echo "OTel Collector deployed. OTLP gRPC: otel-collector-opentelemetry-collector.monitoring.svc.cluster.local:4317"

# Install Grafana (dashboards, auto-provisioned datasources)
obs-grafana:
	#!/usr/bin/env bash
	set -euo pipefail
	helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
	helm repo update grafana
	helm upgrade --install grafana grafana/grafana \
	  --namespace monitoring --create-namespace \
	  --wait --timeout 5m \
	  -f "{{OBS_DIR}}/grafana/values.yaml"
	echo "Grafana ready."
	echo "Port-forward: kubectl port-forward -n monitoring svc/grafana 3000:80"
	echo "Login: admin / homelab-change-me"

# Install full observability stack in correct order
obs-install: obs-victoria-metrics obs-victoria-logs obs-tempo obs-otel-collector obs-grafana
	#!/usr/bin/env bash
	echo ""
	echo "=== Observability stack installed ==="
	kubectl get pods -n monitoring

# Check status of all observability components
obs-status:
	#!/usr/bin/env bash
	echo "=== Pods ==="
	kubectl get pods -n monitoring
	echo ""
	echo "=== PVCs ==="
	kubectl get pvc -n monitoring
	echo ""
	echo "=== Helm releases ==="
	helm list -n monitoring
