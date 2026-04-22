# TinyCA - Step-CA Certificate Authority

Step-CA (smallstep) certificate authority setup on Raspberry Pi, serving as the external root of trust for the homelab.

## Overview

- **Platform**: Raspberry Pi (external to Kubernetes cluster)
- **Root CA**: YubiKey-backed root certificate
- **Purpose**: External PKI root of trust to avoid circular dependencies

## Architecture

```
┌─────────────────────────────────────────────┐
│  Raspberry Pi - Step-CA                     │
│  ┌─────────────┐         ┌───────────────┐ │
│  │   YubiKey   │────────▶│   Root CA     │ │
│  │  (PIV slot) │         │  Certificate  │ │
│  └─────────────┘         └───────────────┘ │
│                                 │           │
│                          ┌──────▼─────────┐ │
│                          │  step-ca       │ │
│                          │  service       │ │
│                          └────────────────┘ │
└──────────────────┬──────────────────────────┘
                   │
                   │ ACME / cert-manager
                   ▼
         ┌─────────────────────┐
         │  Talos K8s Cluster  │
         │  - cert-manager     │
         │  - istio-csr        │
         │  - workload certs   │
         └─────────────────────┘
```

## Design Principles

1. **External Root of Trust**: Step-CA runs outside the cluster to prevent circular dependencies
2. **Hardware-backed Security**: YubiKey stores the root CA private key
3. **Minimal Blast Radius**: Cluster death ≠ CA death ≠ secrets loss
4. **ACME Integration**: cert-manager in cluster uses ACME protocol to obtain certificates

## Components

- **step-ca**: Smallstep certificate authority server
- **YubiKey**: Hardware security module for root CA key storage
- **Provisioners**: ACME, JWK, and OIDC provisioners for certificate issuance

## Configuration Files

- `step-ca-config.json` - Step-CA server configuration
- `bootstrap.sh` - Initial setup script for Raspberry Pi
- `yubikey-setup.md` - YubiKey configuration instructions
- `deployment/` - Systemd service files and deployment automation

## Network Configuration

- **IP Address**: 192.168.1.x (static, TBD)
- **Port**: 9000 (HTTPS)
- **Access**: Reachable from Talos nodes and cluster pods

## Integration with Cluster

The cluster uses **cert-manager** to automatically obtain certificates from Step-CA via ACME:

1. cert-manager configured with Step-CA ACME endpoint
2. istio-csr bridges cert-manager → Istio workload identity
3. All service mesh mTLS uses Step-CA issued certificates
4. No self-signed or in-cluster root CA required

## Setup Guide

This setup follows the official Smallstep guide:

**[Build a Tiny Certificate Authority For Your Homelab](https://smallstep.com/blog/build-a-tiny-ca-with-raspberry-pi-yubikey/)**

### Key Setup Steps

1. **Hardware Setup**: Raspberry Pi 4 + YubiKey 5 NFC
2. **OS Configuration**: Ubuntu Server 64-bit ARM, static IP, NTP sync
3. **PKI Generation**: Root and Intermediate CA keys created offline on USB drive
4. **YubiKey Import**: CA keys stored in PIV slots (9a=root, 9c=intermediate)
5. **step-ca Configuration**: Built with YubiKey support, systemd service integration
6. **ACME Provisioner**: Internal ACME server for automated certificate issuance
7. **Security Hardening**: Firewall enabled, SSH disabled, YubiKey-based service start/stop

### Optional: Infinite Noise TRNG

Hardware random number generator for enhanced entropy generation (feeds `/dev/random`).

## Secrets & SSH Key Recovery

The tinyca admin SSH keypair is stored encrypted in `pki/secrets.sops.yaml` (SOPS + age).

**Prerequisites**: the age private key at `key.txt.secret` in the repo root.

### View decrypted secrets

```bash
SOPS_AGE_KEY_FILE=key.txt.secret sops --decrypt infra/tinyca/pki/secrets.sops.yaml
```

### Restore SSH key files

```bash
# Private key
SOPS_AGE_KEY_FILE=key.txt.secret sops --decrypt --extract '["ssh_private_key"]' \
  infra/tinyca/pki/secrets.sops.yaml > ~/.ssh/tinyca_ed25519
chmod 600 ~/.ssh/tinyca_ed25519

# Public key (optional — derivable from private key via `ssh-keygen -y -f`)
SOPS_AGE_KEY_FILE=key.txt.secret sops --decrypt --extract '["ssh_public_key"]' \
  infra/tinyca/pki/secrets.sops.yaml > ~/.ssh/tinyca_ed25519.pub
```

Load the key into your password manager / SSH agent however you normally would.

> **Note**: `key.txt.secret` is gitignored and lives only at the repo root. Never copy it to
> `~/.config/sops/age/keys.txt` — always pass it explicitly via `SOPS_AGE_KEY_FILE`.

## Setup Status

**Status**: Configured and operational (following Smallstep guide)

See [Architecture Documentation](../docs/ARCHITECTURE.md) for the complete PKI design and integration details.
