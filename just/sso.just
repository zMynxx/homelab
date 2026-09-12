# ── SSO App Provisioning — Kanidm + oauth2-proxy per-app pattern ──────────
#
# Prerequisites:
#   - kanidm client configured (~/.config/kanidm/config with uri + verify_ca)
#   - logged in: kanidm login --name idm_admin
#   - SOPS age key at ./key.txt.secret
#
# Pattern: each app gets its own Kanidm oauth2 client + group + oauth2-proxy
# instance. Only members of <app>_users group can obtain a token (enforced
# at Kanidm scope-map level). The shared oauth2-proxy (192.168.30.203) is
# left unrestricted for ArgoCD.

SSO_DIR  := justfile_directory() + "/infra/k8s/oauth2-proxy"
AGE_KEY  := justfile_directory() + "/key.txt.secret"

# Provision full SSO for a new app — Kanidm client, k8s manifests, SOPS secret, Caddy snippet
# Usage: just sso-add-app grafana "Grafana" 192.168.30.205 192.168.30.206:3000
sso-add-app app display lb_ip upstream:
    #!/usr/bin/env bash
    set -euo pipefail
    APP="{{app}}"
    DISPLAY="{{display}}"
    LB_IP="{{lb_ip}}"
    UPSTREAM="{{upstream}}"
    HOST="${APP}.opnsense.internal"
    REDIRECT_URL="https://${HOST}/oauth2/callback"
    GROUP="${APP}_users"
    COOKIE_NAME="_oauth2_proxy_${APP}"
    K8S_NAME="oauth2-proxy-${APP}"
    SECRET_NAME="oauth2-proxy-${APP}-secrets"

    echo "=== [1/5] Kanidm: group + oauth2 client + scope map ==="
    kanidm group create "${GROUP}" 2>/dev/null || echo "  (group already exists — skipping)"
    kanidm system oauth2 create "${APP}" "${DISPLAY}" "${REDIRECT_URL}" 2>/dev/null || echo "  (client already exists — skipping)"
    kanidm system oauth2 update-scope-map "${APP}" "${GROUP}" openid email profile
    echo "  Group '${GROUP}' mapped to client '${APP}'"

    echo ""
    echo "=== [2/5] Fetching client secret from Kanidm ==="
    CLIENT_SECRET=$(kanidm system oauth2 show-basic-secret "${APP}" 2>/dev/null | tr -d '[:space:]')
    [[ -z "$CLIENT_SECRET" ]] && { echo "ERROR: Could not retrieve client secret. Run: kanidm login --name idm_admin"; exit 1; }
    echo "  Got client secret."

    echo ""
    echo "=== [3/5] Generating cookie secret ==="
    COOKIE_SECRET=$(python3 -c "import secrets,base64; print(base64.urlsafe_b64encode(secrets.token_bytes(32)).decode())")
    echo "  Generated."

    echo ""
    echo "=== [4/5] Writing and encrypting Kubernetes manifests ==="
    RECIPIENT=$(grep 'recipient:' "{{SSO_DIR}}/secrets.sops.yaml" | head -1 | awk '{print $2}')

    PLAIN=$(mktemp /tmp/sso-secret-XXXXXX.yaml)
    trap 'rm -f "$PLAIN"' EXIT
    cat > "$PLAIN" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  namespace: oauth2-proxy
stringData:
  OAUTH2_PROXY_CLIENT_SECRET: "${CLIENT_SECRET}"
  OAUTH2_PROXY_COOKIE_SECRET: "${COOKIE_SECRET}"
EOF
    SOPS_AGE_KEY_FILE="{{AGE_KEY}}" sops --encrypt \
      --age "${RECIPIENT}" \
      "$PLAIN" > "{{SSO_DIR}}/${APP}-secrets.sops.yaml"
    echo "  Written: infra/k8s/oauth2-proxy/${APP}-secrets.sops.yaml"

    cat > "{{SSO_DIR}}/${APP}-deployment.yaml" <<EOF
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${K8S_NAME}
  namespace: oauth2-proxy
  labels:
    app.kubernetes.io/name: ${K8S_NAME}
spec:
  replicas: 2
  selector:
    matchLabels:
      app.kubernetes.io/name: ${K8S_NAME}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: ${K8S_NAME}
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        fsGroup: 65532
      containers:
        - name: oauth2-proxy
          image: quay.io/oauth2-proxy/oauth2-proxy:v7.7.1
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
            seccompProfile:
              type: RuntimeDefault
          args:
            - --provider=oidc
            - --oidc-issuer-url=https://kanidm.kanidm.svc.cluster.local:8443/oauth2/openid/${APP}
            - --insecure-oidc-skip-issuer-verification=true
            - --client-id=${APP}
            - --redirect-url=${REDIRECT_URL}
            - --upstream=static://202
            - --http-address=0.0.0.0:4180
            - --email-domain=*
            - --cookie-domain=.opnsense.internal
            - --cookie-secure=true
            - --cookie-samesite=lax
            - --cookie-name=${COOKIE_NAME}
            - --scope=openid email profile
            - --ssl-insecure-skip-verify=true
            - --set-xauthrequest=true
            - --pass-user-headers=true
            - --skip-provider-button=true
            - --code-challenge-method=S256
            - --whitelist-domain=.opnsense.internal
          env:
            - name: OAUTH2_PROXY_CLIENT_SECRET
              valueFrom:
                secretKeyRef:
                  name: ${SECRET_NAME}
                  key: OAUTH2_PROXY_CLIENT_SECRET
            - name: OAUTH2_PROXY_COOKIE_SECRET
              valueFrom:
                secretKeyRef:
                  name: ${SECRET_NAME}
                  key: OAUTH2_PROXY_COOKIE_SECRET
          ports:
            - name: http
              containerPort: 4180
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 128Mi
          livenessProbe:
            httpGet:
              path: /ping
              port: 4180
            initialDelaySeconds: 10
            periodSeconds: 30
          readinessProbe:
            httpGet:
              path: /ready
              port: 4180
            initialDelaySeconds: 5
            periodSeconds: 10
EOF
    echo "  Written: infra/k8s/oauth2-proxy/${APP}-deployment.yaml"

    cat > "{{SSO_DIR}}/${APP}-service.yaml" <<EOF
---
apiVersion: v1
kind: Service
metadata:
  name: ${K8S_NAME}
  namespace: oauth2-proxy
  annotations:
    lbipam.cilium.io/ips: "${LB_IP}"
spec:
  type: LoadBalancer
  selector:
    app.kubernetes.io/name: ${K8S_NAME}
  ports:
    - name: http
      port: 4180
      targetPort: 4180
EOF
    echo "  Written: infra/k8s/oauth2-proxy/${APP}-service.yaml"

    echo ""
    echo "=== [5/5] Caddy config snippet ==="
    echo "  Add to /usr/local/etc/caddy/caddy.d/${APP}.conf on OPNsense:"
    echo ""
    cat <<CADDY

${HOST} {
    @private {
        not client_ip 192.168.0.0/16
    }
    handle @private {
        abort
    }

    handle /oauth2/* {
        reverse_proxy http://${LB_IP}:4180
    }

    @unauth {
        not header_regexp Cookie "${COOKIE_NAME}="
    }
    handle @unauth {
        redir https://${HOST}/oauth2/sign_in?rd={scheme}://{host}{uri} 302
    }

    handle {
        forward_auth http://${LB_IP}:4180 {
            uri /oauth2/auth
            copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
        }
        reverse_proxy ${UPSTREAM}
    }
}

CADDY

    echo "=== Done! Next steps ==="
    echo "  1. git add infra/k8s/oauth2-proxy/${APP}-*.yaml && git push"
    echo "     ArgoCD auto-syncs — no new Application needed."
    echo "  2. SSH to OPNsense, add the Caddy config above, reload Caddy"
    echo "  3. Upload logo:  just sso-set-logo ${APP} /path/to/logo.png"
    echo "  4. Add users:    just sso-add-user ${APP} <username>"

# Upload a logo image for an app in Kanidm (PNG, WEBP, or SVG)
# Usage: just sso-set-logo adguard /path/to/adguard.png
sso-set-logo app logo_path:
    kanidm system oauth2 set-image "{{app}}" "{{logo_path}}"
    @echo "Logo set for {{app}}"

# Add a user to an app's access group
# Usage: just sso-add-user adguard lior
sso-add-user app username:
    kanidm group add-members "{{app}}_users" "{{username}}"
    @echo "{{username}} added to {{app}}_users"

# Remove a user from an app's access group
# Usage: just sso-remove-user adguard lior
sso-remove-user app username:
    kanidm group remove-members "{{app}}_users" "{{username}}"
    @echo "{{username}} removed from {{app}}_users"

# List members of an app's access group
# Usage: just sso-list-users adguard
sso-list-users app:
    kanidm group get "{{app}}_users"

# List all SSO apps registered in Kanidm
sso-list-apps:
    kanidm system oauth2 list

# Rotate client secret for an app — re-encrypts SOPS secret, prints rollout command
# Usage: just sso-rotate-secret adguard
sso-rotate-secret app:
    #!/usr/bin/env bash
    set -euo pipefail
    APP="{{app}}"
    SECRET_NAME="oauth2-proxy-${APP}-secrets"
    RECIPIENT=$(grep 'recipient:' "{{SSO_DIR}}/secrets.sops.yaml" | head -1 | awk '{print $2}')

    echo "Resetting client secret for ${APP} in Kanidm..."
    kanidm system oauth2 reset-secrets "${APP}"
    CLIENT_SECRET=$(kanidm system oauth2 show-basic-secret "${APP}" 2>/dev/null | tr -d '[:space:]')
    [[ -z "$CLIENT_SECRET" ]] && { echo "ERROR: Could not retrieve new secret."; exit 1; }

    COOKIE_SECRET=$(python3 -c "import secrets,base64; print(base64.urlsafe_b64encode(secrets.token_bytes(32)).decode())")

    PLAIN=$(mktemp /tmp/sso-secret-XXXXXX.yaml)
    trap 'rm -f "$PLAIN"' EXIT
    cat > "$PLAIN" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  namespace: oauth2-proxy
stringData:
  OAUTH2_PROXY_CLIENT_SECRET: "${CLIENT_SECRET}"
  OAUTH2_PROXY_COOKIE_SECRET: "${COOKIE_SECRET}"
EOF
    SOPS_AGE_KEY_FILE="{{AGE_KEY}}" sops --encrypt \
      --age "${RECIPIENT}" \
      "$PLAIN" > "{{SSO_DIR}}/${APP}-secrets.sops.yaml"

    echo "Secret rotated and re-encrypted: infra/k8s/oauth2-proxy/${APP}-secrets.sops.yaml"
    echo "Push to git then force a rollout:"
    echo "  kubectl rollout restart deploy/oauth2-proxy-${APP} -n oauth2-proxy"
