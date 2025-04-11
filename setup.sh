#!/bin/bash

# This script is to be run at the root of the repository to configure the repository for applicaiton exploration.

# What inputs are needed?
#   - application name being explored
#   - optionally allow a port(s) to be specified for the cluster to expose ingress
#   - nubmer of k3d servers
#   - nubmer of k3d agents
#   - Memory limit for k3d cluster
#   - CPU limit for k3d cluster
#   - Specify justfile version

# Write function to update k3d/k3d-config.yaml with the ports that are not currently in use

# Write a function to update the just file according to the inputs

# Set just version via asdf