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

    # Create clean directory on VM (remove old demo files)
    $SSH "rm -rf ~/container-freeze/current-demo && mkdir -p ~/container-freeze/current-demo"

    # Copy demo files
    print_step "Copying demo files..."
    $SCP -r "$demo_path"/* cfuser@$VM_IP:~/container-freeze/current-demo/

    # Copy shared utilities
    $SCP -r "$PROJECT_ROOT/response" cfuser@$VM_IP:~/container-freeze/
    $SCP -r "$PROJECT_ROOT/forensics" cfuser@$VM_IP:~/container-freeze/

    # Build images (read from demo.yaml)
    print_step "Building container images..."

    # Parse demo.yaml for image definitions
    local image_builds=""
    if [ -f "$demo_path/demo.yaml" ]; then
        # Extract image definitions from demo.yaml using awk for reliable multi-entry parsing
        # This handles the images: section and extracts name/path pairs
        image_builds=$(awk '
            /^images:/ { in_images=1; next }
            /^[a-z]/ { if (substr($0,1,2) != "  ") in_images=0 }
            in_images && /^  - name:/ {
                gsub(/^  - name: */, "")
                gsub(/["'"'"']/, "")
                name=$0
            }
            in_images && /^    path:/ {
                gsub(/^    path: */, "")
                gsub(/["'"'"']/, "")
                if (name != "") {
                    print name "|" $0
                    name=""
                }
            }
        ' "$demo_path/demo.yaml" 2>/dev/null)

        # Show discovered images
        while IFS='|' read -r img_name img_path; do
            [ -z "$img_name" ] && continue
            echo "  Found image: $img_name at $img_path"
        done <<< "$image_builds"
    fi

    if [ -n "$image_builds" ]; then
        # Use demo.yaml definitions
        echo "  Building and importing images..."
        while IFS='|' read -r img_name img_path; do
            [ -z "$img_name" ] && continue
            echo "  Processing $img_name..."

            # Build and import image on VM
            # Note: < /dev/null prevents SSH from consuming stdin (which breaks the while loop)
            if ! $SSH "cd ~/container-freeze/current-demo && \
                if [ ! -d '$img_path' ]; then \
                    echo 'ERROR: Directory $img_path not found'; \
                    exit 1; \
                fi; \
                if [ ! -f '$img_path/Dockerfile' ]; then \
                    echo 'ERROR: Dockerfile not found in $img_path'; \
                    exit 1; \
                fi; \
                echo '  -> Building Docker image...'; \
                sudo docker build -t 'localhost/$img_name:latest' '$img_path' || exit 1; \
                echo '  -> Saving and importing to k3s...'; \
                sudo docker save 'localhost/$img_name:latest' | sudo k3s ctr images import - || exit 1; \
                echo '  -> Verifying import...'; \
                sudo k3s ctr images ls | grep -q 'localhost/$img_name:latest' || exit 1; \
                echo '  ✓ localhost/$img_name:latest imported successfully'" < /dev/null; then
                print_error "Failed to build/import image: $img_name"
                print_error "Check that Docker and k3s are running on the VM"
                return 1
            fi
        done <<< "$image_builds"

        # Final verification
        print_step "Verifying all images are available..."
        local all_ok=true
        while IFS='|' read -r img_name img_path; do
            [ -z "$img_name" ] && continue
            if $SSH "sudo k3s ctr images ls | grep -q 'localhost/$img_name:latest'" < /dev/null; then
                echo "  ✓ localhost/$img_name:latest"
            else
                print_error "Image not found: localhost/$img_name:latest"
                all_ok=false
            fi
        done <<< "$image_builds"

        if [ "$all_ok" = false ]; then
            print_error "Some images failed to import"
            return 1
        fi
    else
        # Fallback to legacy hardcoded dirs for backward compatibility
        echo "  No images defined in demo.yaml, using legacy detection..."
        $SSH << 'REMOTE_BUILD'
cd ~/container-freeze/current-demo
for img_dir in app malware c2-server payload-server; do
    if [ -d "$img_dir" ] && [ -f "$img_dir/Dockerfile" ]; then
        name=$(basename "$img_dir")
        case "$name" in
            app) image_name="vulnerable-app" ;;
            malware) image_name="sleepy-malware" ;;
            c2-server) image_name="c2-server" ;;
            *) image_name="$name" ;;
        esac
        echo "  Building $image_name from $img_dir..."
        sudo docker build -t "localhost/$image_name:latest" "./$img_dir" || exit 1
        echo "  Importing to k3s..."
        sudo docker save "localhost/$image_name:latest" | sudo k3s ctr images import - || exit 1
        echo "  ✓ $image_name imported"
    fi
done
REMOTE_BUILD
        if [ $? -ne 0 ]; then
            print_error "Failed to build images using legacy method"
            return 1
        fi
    fi

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

    # Apply deployments (read from demo.yaml)
    print_step "Deploying workloads..."

    # Extract deployment files from demo.yaml (stop at next top-level key)
    local deployment_files=""
    if [ -f "$demo_path/demo.yaml" ]; then
        deployment_files=$(awk '/^deployments:/{found=1; next} /^[a-z]/{found=0} found && /^  - /{gsub(/^  - ["'"'"']?|["'"'"']?$/,""); print}' "$demo_path/demo.yaml" 2>/dev/null || echo "")
    fi

    if [ -n "$deployment_files" ]; then
        # Apply deployments in order from demo.yaml
        while IFS= read -r deploy_file; do
            [ -z "$deploy_file" ] && continue
            echo "  Applying $deploy_file..."
            # Note: < /dev/null prevents SSH from consuming stdin (which breaks the while loop)
            $SSH "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && \
                cd ~/container-freeze/current-demo && \
                kubectl apply -f '$deploy_file'" < /dev/null
        done <<< "$deployment_files"
    else
        # Fallback to legacy hardcoded paths
        $SSH << 'REMOTE_DEPLOY'
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
cd ~/container-freeze/current-demo
[ -f c2-server/deployment.yaml ] && kubectl apply -f c2-server/deployment.yaml
[ -f app/deployment.yaml ] && kubectl apply -f app/deployment.yaml
REMOTE_DEPLOY
    fi

    # Wait for pods
    print_step "Waiting for pods..."
    $SSH "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && \
        kubectl wait --for=condition=ready pod -l app -A --timeout=120s 2>/dev/null || true"

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

# Rerun demo from scratch (reset + redeploy + run)
# Usage: rerun_demo_from_scratch <demo_path>
rerun_demo_from_scratch() {
    local demo_path="$1"
    local demo_name=$(basename "$demo_path")
    local current_demo=$(get_current_demo)

    print_header "Rerunning Demo from Scratch: $(get_demo_info "$demo_path" "display_name")"
    print_warning "This will reset the K3s cluster, redeploy, and run the demo"

    if [ -n "$current_demo" ]; then
        print_step "Current demo: '$current_demo'"
    fi

    if ! gum confirm "Continue with full reset?"; then
        return 0
    fi

    # Step 1: Clean K3s for fresh state
    print_step "Step 1/3: Cleaning K3s cluster..."
    gum spin --spinner dot --title "Uninstalling K3s..." -- "$PROJECT_ROOT/cleanup-cluster.sh"

    print_step "Reinstalling K3s..."
    gum spin --spinner dot --title "Installing K3s..." -- "$PROJECT_ROOT/vm/install-k3s.sh"

    # Step 2: Deploy the demo
    print_step "Step 2/3: Deploying demo..."
    deploy_demo "$demo_path"

    if [ $? -ne 0 ]; then
        print_error "Failed to deploy demo"
        return 1
    fi

    # Step 3: Run the demo
    print_step "Step 3/3: Running demo..."
    run_demo "$demo_path"
}
