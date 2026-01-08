#!/bin/bash
# Container Freeze - Demo management functions
# Discovery, deployment, and switching of demo scenarios

# Get project root (should be set by main script)
: "${PROJECT_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

DEMOS_DIR="$PROJECT_ROOT/demos"
VM_DIR="$PROJECT_ROOT/vm"
CURRENT_DEMO_FILE="$VM_DIR/current-demo.env"

# Discover all available demos
# Returns list of demo directory paths
discover_demos() {
    local demos_dir="$DEMOS_DIR"
    for demo_yaml in "$demos_dir"/*/demo.yaml; do
        if [ -f "$demo_yaml" ]; then
            dirname "$demo_yaml"
        fi
    done
}

# Get demo info from demo.yaml
# Usage: get_demo_info <demo_path> <field>
get_demo_info() {
    local demo_path="$1"
    local field="$2"
    local demo_yaml="$demo_path/demo.yaml"

    if [ ! -f "$demo_yaml" ]; then
        echo ""
        return 1
    fi

    # Simple YAML parsing (works for flat fields)
    grep "^${field}:" "$demo_yaml" 2>/dev/null | sed "s/^${field}:[[:space:]]*//" | sed 's/^["'"'"']//' | sed 's/["'"'"']$//'
}

# Get current deployed demo
get_current_demo() {
    if [ -f "$CURRENT_DEMO_FILE" ]; then
        source "$CURRENT_DEMO_FILE"
        echo "$CURRENT_DEMO"
    else
        echo ""
    fi
}

# Get current demo path
get_current_demo_path() {
    if [ -f "$CURRENT_DEMO_FILE" ]; then
        source "$CURRENT_DEMO_FILE"
        echo "$CURRENT_DEMO_PATH"
    else
        echo ""
    fi
}

# List demos with their display names and descriptions
# Output format: path|display_name|description
list_demos_formatted() {
    while IFS= read -r demo_path; do
        local name=$(get_demo_info "$demo_path" "display_name")
        local desc=$(get_demo_info "$demo_path" "description")
        local demo_name=$(basename "$demo_path")

        # Fallback to directory name if no display_name
        [ -z "$name" ] && name="$demo_name"
        [ -z "$desc" ] && desc="No description"

        echo "$demo_path|$name|$desc"
    done < <(discover_demos)
}

# Deploy a specific demo
# Usage: deploy_demo <demo_path>
deploy_demo() {
    local demo_path="$1"
    local demo_name=$(basename "$demo_path")

    if [ ! -f "$VM_DIR/connection.env" ]; then
        print_error "VM not set up. Run setup first."
        return 1
    fi

    source "$VM_DIR/connection.env"
    local SSH="ssh -i $SSH_KEY -o StrictHostKeyChecking=no cfuser@$VM_IP"
    local SCP="scp -i $SSH_KEY -o StrictHostKeyChecking=no"

    print_step "Deploying demo: $demo_name"

    # Create directory on VM
    $SSH "mkdir -p ~/container-freeze/current-demo"

    # Copy demo files
    print_step "Copying demo files..."
    $SCP -r "$demo_path"/* cfuser@$VM_IP:~/container-freeze/current-demo/

    # Copy shared utilities
    $SCP -r "$PROJECT_ROOT/response" cfuser@$VM_IP:~/container-freeze/
    $SCP -r "$PROJECT_ROOT/forensics" cfuser@$VM_IP:~/container-freeze/

    # Build images
    print_step "Building container images..."
    $SSH << 'REMOTE_BUILD'
cd ~/container-freeze/current-demo
for img_dir in app malware c2-server; do
    if [ -d "$img_dir" ] && [ -f "$img_dir/Dockerfile" ]; then
        name=$(basename "$img_dir")
        case "$name" in
            app) image_name="vulnerable-app" ;;
            malware) image_name="sleepy-malware" ;;
            c2-server) image_name="c2-server" ;;
            *) image_name="$name" ;;
        esac
        echo "Building $image_name..."
        sudo docker build -t "localhost/$image_name:latest" "./$img_dir"
        sudo docker save "localhost/$image_name:latest" | sudo k3s ctr images import -
    fi
done
REMOTE_BUILD

    # Apply detection policies (Tetragon installed as base infrastructure in install-k3s.sh)
    print_step "Applying detection policies..."
    $SSH << 'REMOTE_POLICIES'
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
cd ~/container-freeze/current-demo
if [ -d "detection" ]; then
    echo "Applying TracingPolicies..."
    for policy in detection/tracing-policy-*.yaml; do
        if [ -f "$policy" ]; then
            echo "  Applying $policy"
            kubectl apply -f "$policy"
        fi
    done
fi
REMOTE_POLICIES

    # Apply deployments
    print_step "Deploying workloads..."
    $SSH << 'REMOTE_DEPLOY'
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
cd ~/container-freeze/current-demo
# Apply c2-server first if exists
[ -f c2-server/deployment.yaml ] && kubectl apply -f c2-server/deployment.yaml
# Apply main app deployment
[ -f app/deployment.yaml ] && kubectl apply -f app/deployment.yaml
# Wait for pods
echo "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app -A --timeout=120s 2>/dev/null || true
REMOTE_DEPLOY

    # Update state file
    cat > "$CURRENT_DEMO_FILE" << EOF
CURRENT_DEMO=$demo_name
CURRENT_DEMO_PATH=$demo_path
DEPLOYED_AT=$(date -Iseconds)
EOF

    print_success "Demo '$demo_name' deployed successfully"
}

# Run a demo's run script
# Usage: run_demo <demo_path>
run_demo() {
    local demo_path="$1"
    local demo_name=$(basename "$demo_path")

    if [ ! -f "$VM_DIR/connection.env" ]; then
        print_error "VM not set up."
        return 1
    fi

    source "$VM_DIR/connection.env"

    print_header "Running Demo: $(get_demo_info "$demo_path" "display_name")"

    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -t cfuser@"$VM_IP" \
        "cd ~/container-freeze/current-demo && ./run.sh"
}

# Switch to a different demo (full K3s reset)
# Usage: switch_demo <demo_path>
switch_demo() {
    local new_demo_path="$1"
    local new_demo_name=$(basename "$new_demo_path")
    local current_demo=$(get_current_demo)

    # Check if same demo
    if [ "$current_demo" = "$new_demo_name" ]; then
        print_warning "Demo '$new_demo_name' is already deployed"
        if ! gum confirm "Redeploy anyway?"; then
            return 0
        fi
    elif [ -n "$current_demo" ]; then
        print_step "Switching from '$current_demo' to '$new_demo_name'"
        print_warning "This will reset the K3s cluster for a clean state"
        if ! gum confirm "Continue?"; then
            return 0
        fi
    fi

    # Clean K3s for fresh state
    print_step "Cleaning K3s cluster..."
    gum spin --spinner dot --title "Uninstalling K3s..." -- "$PROJECT_ROOT/cleanup-cluster.sh"

    print_step "Reinstalling K3s..."
    gum spin --spinner dot --title "Installing K3s..." -- "$PROJECT_ROOT/vm/install-k3s.sh"

    # Deploy the new demo
    deploy_demo "$new_demo_path"
}
