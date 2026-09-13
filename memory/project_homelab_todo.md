# Homelab TODO — Future Sessions

## SSO / OIDC
1. Set logo for oauth2-proxy on Kanidm
2. Verify AdGuard OIDC works
3. Set up OIDC for the rest of the services (Longhorn UI, Cilium Hubble, Grafana UI, Istio UI, Zot UI, etc — everything with a UI)
4. Set homelab CA certs for OPNsense behind Caddy, and set up OIDC

## Caddy / PKI
5. Make sure Caddy is using our homelab's TinyCA certificate
6. Set client certificate validations on Caddy
7. Make sure we have each of Caddy's services/servers config in a separate file, tracked by git
8. Make sure we have the Caddyfile config (should be basic + import) tracked by git

## DNS / Networking
9. Finish setting up AdGuard provider for ExternalDNS

## Resilience / Ops
10. Make sure we have all the crucial stuff in HA using DaemonSets / multiple pods
11. Ensure stability and usage
12. Make sure we can take it all apart and back to the same status with ease (scripts, justfiles, etc — everything well documented and re-usable)
13. Improve

## Experimental
14. Test out OpenChoreo usage for homelab
