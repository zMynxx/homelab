# SSO Operations - Kanidm + oauth2-proxy
#
# OAuth2 clients, groups, and users are managed declaratively via kaniop CRDs
# in gitops/platform/wave-0/kanidm/. Use these recipes only for operations
# that have no CRD equivalent (logo upload, secret rotation).
#
# Prerequisites:
#   - kanidm client configured (~/.config/kanidm/config with uri + verify_ca)
#   - logged in: kanidm login --name idm_admin
#   - SOPS age key at ./key.txt.secret

SSO_DIR := justfile_directory() + "/gitops/platform/wave-2/oauth2-proxy"

# Generate a one-time credential reset link for a user (no CRD equivalent)
# Usage: just sso-reset-credentials lior
sso-reset-credentials username:
	kanidm person credential create-reset-token --name idm_admin {{username}}

# Upload a logo image for an app in Kanidm (PNG, WEBP, or SVG)
# Usage: just sso-set-logo adguard /path/to/adguard.png
sso-set-logo app logo_path:
	kanidm system oauth2 set-image {{app}} {{logo_path}}
	@echo "Logo set for {{app}}"

# Add a user to an app's access group (prefer editing KanidmGroup CRD in gitops)
# Usage: just sso-add-user adguard lior
sso-add-user app username:
	kanidm group add-members {{app}}_users {{username}}
	@echo "{{username}} added to {{app}}_users"

# Remove a user from an app's access group
# Usage: just sso-remove-user adguard lior
sso-remove-user app username:
	kanidm group remove-members {{app}}_users {{username}}
	@echo "{{username}} removed from {{app}}_users"

# List members of an app's access group
# Usage: just sso-list-users adguard
sso-list-users app:
	kanidm group get {{app}}_users

# List all SSO apps registered in Kanidm
sso-list-apps:
	kanidm system oauth2 list

# Rotate client secret for an app — fetches new secret from Kanidm, re-encrypts
# as SopsSecret, commits. ArgoCD + sops-secrets-operator apply it automatically.
# Usage: just sso-rotate-secret adguard
sso-rotate-secret app:
	bash -c 'set -euo pipefail; \
	  APP={{app}}; \
	  SECRET_NAME="oauth2-proxy-${APP}-secrets"; \
	  CLIENT_SECRET=$(kanidm system oauth2 show-basic-secret "${APP}" 2>/dev/null | tr -d "[:space:]"); \
	  COOKIE_SECRET=$(python3 -c "import secrets,base64; print(base64.urlsafe_b64encode(secrets.token_bytes(32)).decode())"); \
	  PLAIN=$(mktemp /tmp/sso-secret-XXXXXX.yaml); \
	  printf "apiVersion: isindir.github.com/v1alpha3\nkind: SopsSecret\nmetadata:\n  name: %s\n  namespace: oauth2-proxy\nspec:\n  secretTemplates:\n    - name: %s\n      stringData:\n        OAUTH2_PROXY_CLIENT_SECRET: \"%s\"\n        OAUTH2_PROXY_COOKIE_SECRET: \"%s\"\n" "$SECRET_NAME" "$SECRET_NAME" "$CLIENT_SECRET" "$COOKIE_SECRET" > "$PLAIN"; \
	  SOPS_AGE_KEY_FILE={{AGE_KEY}} sops --encrypt "$PLAIN" > {{SSO_DIR}}/${APP}-secrets.sops.yaml; \
	  rm -f "$PLAIN"; \
	  echo "Secret rotated: gitops/platform/wave-2/oauth2-proxy/${APP}-secrets.sops.yaml"; \
	  echo "Run: kubectl rollout restart deploy/oauth2-proxy-${APP} -n oauth2-proxy"'
