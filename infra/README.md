# Infrastructure Layer

This directory contains physical infrastructure setup and cluster configuration.

## Contents

### Kubernetes Cluster
- **talos/** - Talos Linux cluster configuration
  - TuringPi2 with RK1 ARM64 nodes
  - Ansible playbooks for cluster bootstrapping
  - Declarative OS configuration

### PKI / Certificate Authority
- **tinyca/** - Step-CA (smallstep) certificate authority setup
  - Raspberry Pi deployment
  - YubiKey-backed root certificate
  - External root of trust for the cluster

### Documentation
- **docs/** - Architecture documentation and design decisions
  - ARCHITECTURE.md - Complete homelab design document

## Infrastructure Components

- **TuringPi2** - Kubernetes cluster (3x Turing RK1 ARM64 nodes)
- **Raspberry Pi** - Step-CA certificate authority (tinyca)
- **TrueNAS** - Network storage (future)

## Current Focus

Active development is on the Talos Kubernetes cluster and Step-CA PKI infrastructure. Legacy Proxmox/Terraform/Ansible configurations have been moved to `old/` directory for reference.
