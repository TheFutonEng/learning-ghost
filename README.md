# K8s Learning Template

This repo is a template to duplicate when exploring a new K8s based project / application.

# Dependencies

This repo requires the following tools:

- `just` (tested with 1.36.0)
- `k3d` (tested with 5.8.1)
- `yq` (tested with v4.44.5)
- `go` (tested with 1.24.2)

A quick way to take care of `just` and `go` if the [`asdf`](https://asdf-vm.com/) version manager is in use on a system is to run the `setup-tools.sh` script:

```bash
$ ./setup-tools.sh
Checking required tools.
Installing just version 1.36.0.
just 1.36.0 is already installed
just 1.36.0 is ready
Installing golang version 1.24.2.
golang 1.24.2 is already installed
golang 1.24.2 is ready
All required tools are installed and configured!
```

`k3d` and `yq` need to be installed via other means

# K3d Cluster Templater

This tool helps you quickly create K3d cluster configurations with automated port allocation and customizable parameters.

## Features
- Automatically finds available ports for API server, HTTP, and HTTPS
- Template-based configuration generation
- Customizable server and agent counts, CPU, and memory allocations

## Installation
```bash
go build -o k3d-templater k3d-templater.go
```

Alternatively, call the `compile-templater` target:

```bash
just compile-templater
```

## Usage

Basic usage (required cluster name):

``` bash
./k3d-templater -name my-project
```

All available options:

```bash
./k3d-templater -name my-project -servers 2 -agents 3 -memory 2gb -cpu 2 -template custom-template.yaml -output my-config.yaml
```

## Parameters

| Flag | Description | Default |
| ---- | ----------- | ------- |
| `-name` |	Cluster name (required)	| none |
| `-servers` |	Number of K3d servers	| 1 |
| `-agents`	| Number of K3d agents | 0 |
| `-memory` |	Memory allocation for servers	| "1gb" |
| `-cpu` | CPU allocation for servers | "1" |
| `-template` |	Path to template file	| "k3d-template.yaml" |
| `-output` |	Output file path | "k3d-{name}.yaml" |

## Integration with `just`
Add this to your justfile to easily create and start clusters:

```bash
# Create a new K3d cluster configuration
create-cluster NAME SERVERS="1" AGENTS="0" MEMORY="1gb" CPU="1":
    ./k3d-templater -name {{NAME}} -servers {{SERVERS}} -agents {{AGENTS}} -memory {{MEMORY}} -cpu {{CPU}}
    k3d cluster create --config k3d-{{NAME}}.yaml

# Delete a K3d cluster
delete-cluster NAME:
    k3d cluster delete {{NAME}}
```

### Example

```bash
./k3d-templater -name webapp -servers 2 -memory 2gb
k3d cluster create --config k3d-webapp.yaml
```

## `just` Targets

```bash
$ just
Available recipes:
    compile-templater          # Compile k3d-templater
    create-cluster-config NAME # Create a new K3d cluster configuration
    create-custom-cluster-config NAME SERVERS="2" AGENTS="1" MEMORY="2gb" CPU="2" # Create a K3d cluster with custom configuration
    default                    # List available recipes
    delete-ca-integration      # Delete step-issuer
    delete-cert-manager        # Delete cert-manager
    delete-cluster             # Delete k3d cluster and clean up resources
    delete-ingress             # Clean up HAProxy
    delete-step-issuer         # Delete step-issuer
    delete-wildcard-cert       # Create wildcard certificate for *.wsp.local
    deploy-cert-manager        # Deploy cert-manager
    deploy-cluster             # Create k3d cluster using configuration file
    deploy-ingress             # Deploy HAProxy ingress controller
    deploy-step-issuer         # Deploy step-issuer
    deploy-wildcard-cert       # Create wildcard certificate for *.wsp.local
    reset-all NAME             # Reset everything and create a fresh cluster with all components
    setup-ca-integration       # Setup CA integration with step-issuer
```

As noted above, there are a lot of components that get deployed as part of the template.  This is to integrate with the created cluster with the PKI infrastructure of my home lab.  If someone else is consuming this template, it will need to be updated to accommodate your PKI infrastructure.  For a `step-ca` specific example, see the `step-ca-integration-example.yaml` file for details on what needs to be provided.  Once filled out, rename that file to `step-ca-integration-values.yaml` and run `just reset-all`.  The `step-ca-integration-values.yaml` file is present in `.gitignore` so sensitive data isn't accidentally pushed to a git server.