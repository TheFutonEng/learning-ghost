# List available recipes
default:
    @just --list

# Create k3d cluster using configuration file
deploy-cluster: delete-cluster
    #!/usr/bin/env sh
    echo "Creating k3d cluster."
    k3d cluster create --config k3d/k3d-config.yaml

    # Wait for cluster to be ready
    echo "Waiting for cluster to be ready."
    kubectl wait --for=condition=ready node --all --timeout=60s

# Delete k3d cluster and clean up resources
delete-cluster:
    #!/usr/bin/env sh

    if ! [ -f ./k3d/k3d-config.yaml ]; then
        echo "No cluster configuration file found."
        exit 0
    fi

    clusterName=$(yq .metadata.name k3d/k3d-config.yaml)

    if k3d cluster list | grep -q "$clusterName"; then
        echo "Deleting existing cluster."
        k3d cluster delete $clusterName
        echo "Cleaning up resources."
        docker network rm k3d-$clusterName 2>/dev/null || true
        docker volume rm k3d-$clusterName-images 2>/dev/null || true
    else
      echo "Cluster does not exist"
    fi

# Deploy HAProxy ingress controller
deploy-ingress:
    #!/usr/bin/env sh
    echo "Creating ingress-controller namespace."
    kubectl create namespace ingress-controller --dry-run=client -o yaml | kubectl apply -f -

    echo "Adding HAProxy helm repository."
    helm repo add haproxytech https://haproxytech.github.io/helm-charts
    helm repo update

    echo "Cleaning up any existing HAProxy resources."
    kubectl delete configmap -n ingress-controller haproxy-ingress --ignore-not-found

    echo "Deploying HAProxy ingress controller."
    helm upgrade --install haproxy-ingress haproxytech/kubernetes-ingress \
        --namespace ingress-controller \
        -f k8s/haproxy-values.yaml \
        --wait

    echo "Waiting for HAProxy ingress controller to be ready."
    kubectl wait --namespace ingress-controller \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/name=kubernetes-ingress \
        --timeout=300s

    echo "HAProxy ingress controller deployment status:"
    kubectl get pods,svc -n ingress-controller

# Clean up HAProxy
delete-ingress:
    #!/usr/bin/env sh
    echo "Removing HAProxy ingress controller."
    helm uninstall haproxy-ingress -n ingress-controller || true
    # kubectl delete namespace ingress-controller || true

# Deploy cert-manager
deploy-cert-manager:
    #!/usr/bin/env sh
    echo "Creating cert-manager namespace"
    kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -

    echo "Adding jetstack helm repository"
    helm repo add jetstack https://charts.jetstack.io
    helm repo update

    echo "Installing cert-manager with CRDs"
    helm upgrade --install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --set installCRDs=true \
        --set global.leaderElection.namespace=cert-manager \
        --wait

    echo "Waiting for cert-manager pods to be ready"
    kubectl wait --namespace cert-manager \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/instance=cert-manager \
        --timeout=300s

    echo "cert-manager deployment status:"
    kubectl get pods -n cert-manager

# Delete cert-manager
delete-cert-manager:
    #!/usr/bin/env sh
    echo "Removing cert-manager"
    helm uninstall cert-manager -n cert-manager || true
    kubectl delete namespace cert-manager || true

# Deploy step-issuer
deploy-step-issuer:
    #!/usr/bin/env sh
    echo "Creating step-issuer namespace"
    kubectl create namespace step-issuer --dry-run=client -o yaml | kubectl apply -f -

    echo "Adding smallstep helm repository"
    helm repo add smallstep https://smallstep.github.io/helm-charts
    helm repo update

    echo "Installing step-issuer"
    helm upgrade --install step-issuer smallstep/step-issuer \
        --namespace step-issuer \
        --set step-issuer.create=true \
        --wait

    echo "Waiting for step-issuer to be ready"
    kubectl wait --namespace step-issuer \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/name=step-issuer \
        --timeout=300s

    echo "step-issuer deployment status:"
    kubectl get pods -n step-issuer -l app.kubernetes.io/name=step-issuer

# Delete step-issuer
delete-step-issuer:
    #!/usr/bin/env sh
    echo "Removing step-issuer"
    helm uninstall step-issuer -n step-issuer || true
    kubectl delete namespace step-issuer || true

# Setup CA integration with step-issuer
setup-ca-integration:
    helm upgrade --install step-ca-integration ./charts/step-ca-integration \
        -f step-ca-integration-values.yaml \
        --namespace step-issuer \
        --create-namespace

# Delete step-issuer
delete-ca-integration:
    #!/usr/bin/env sh
    echo "Removing step-issuer"
    helm uninstall step-ca-integration -n step-issuer || true

# Create wildcard certificate for *.wsp.local
deploy-wildcard-cert:
    #!/usr/bin/env sh
    echo "Creating wildcard certificate for *.wsp.local"
    kubectl apply -f k8s/certificate.yaml

    echo "Waiting for certificate to be ready..."
    kubectl wait --namespace ingress-controller \
        --for=condition=Ready \
        certificate/wsp-local-wildcard \
        --timeout=300s

    echo "Certificate status:"
    kubectl get certificate -n ingress-controller wsp-local-wildcard

    echo "Rolling restart of HAProxy DaemonSet..."
    kubectl rollout restart daemonset -n ingress-controller -l app.kubernetes.io/name=kubernetes-ingress

    echo "Waiting for HAProxy rollout to complete..."
    kubectl rollout status daemonset -n ingress-controller -l app.kubernetes.io/name=kubernetes-ingress --timeout=300s


# Create wildcard certificate for *.wsp.local
delete-wildcard-cert:
    #!/usr/bin/env sh
    echo "Deleting wildcard certificate for *.wsp.local"
    kubectl delete -f k8s/certificate.yaml

# Add task to deploy component under exploration

# Add task to delete component under exploration

# Reset everything and create a fresh cluster with all components
reset-all NAME:
    #!/usr/bin/env sh
    echo "Resetting all components and cluster."

    echo "Creating new cluster configuration."
    just create-cluster-config {{NAME}}

    echo "Deploying fresh cluster."
    just deploy-cluster

    echo "Deploying HAProxy ingress."
    just deploy-ingress

    echo "Deploying cert-manager."
    just deploy-cert-manager

    echo "Deploying step-issuer."
    just deploy-step-issuer

    echo "Setting up integration with step CA"
    just setup-ca-integration

    echo "Waiting for all pods to be ready."
    kubectl wait --for=condition=ready pod -n ingress-controller --selector '!job-name' --timeout=300s
    kubectl wait --for=condition=ready pod --all -n cert-manager --timeout=300s

    # Add deployment tasks for components under exploration here

# Compile k3d-templater
compile-templater:
    go build -o k3d-templater ./go/k3d-templater.go

# Create a new K3d cluster configuration
create-cluster-config NAME: compile-templater
    ./k3d-templater -name {{NAME}}

# Create a K3d cluster with custom configuration
create-custom-cluster-config NAME SERVERS="2" AGENTS="1" MEMORY="2gb" CPU="2":
    ./k3d-templater -name {{NAME}} -servers {{SERVERS}} -agents {{AGENTS}} -memory {{MEMORY}} -cpu {{CPU}}
    k3d cluster create --config k3d-{{NAME}}.yaml