#!/bin/bash
# Build Container Images and Cache Locally
# This speeds up subsequent POC deployments by pre-building images

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

CACHE_DIR="./image-cache"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║         Container Freeze - Build and Cache Images            ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "This will build all POC container images and cache them locally."
echo "Cached images speed up deployment from ~4 minutes to ~30 seconds."
echo ""

# Check for Docker
if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker is not installed or not in PATH"
    echo "Install Docker: https://docs.docker.com/get-docker/"
    exit 1
fi

# Create cache directory
mkdir -p "$CACHE_DIR"

START_TIME=$(date +%s)

# Build images
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Building Images"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "[1/3] Building vulnerable-app..."
docker build -t localhost/vulnerable-app:latest ./vulnerable-app

echo ""
echo "[2/3] Building sleepy-malware..."
docker build -t localhost/sleepy-malware:latest ./malware

echo ""
echo "[3/3] Building c2-server..."
docker build -t localhost/c2-server:latest ./c2-server

# Save to tarballs
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Saving Image Cache"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Exporting vulnerable-app..."
docker save localhost/vulnerable-app:latest -o "$CACHE_DIR/vulnerable-app.tar"

echo "Exporting sleepy-malware..."
docker save localhost/sleepy-malware:latest -o "$CACHE_DIR/sleepy-malware.tar"

echo "Exporting c2-server..."
docker save localhost/c2-server:latest -o "$CACHE_DIR/c2-server.tar"

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    BUILD COMPLETE                             ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "✓ Images cached in: $CACHE_DIR/"
echo ""
echo "Cached files:"
ls -lh "$CACHE_DIR/"/*.tar 2>/dev/null || echo "  (none)"
echo ""

# Calculate total size
if command -v du &> /dev/null; then
    TOTAL_SIZE=$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1)
    echo "Total cache size: $TOTAL_SIZE"
fi

echo "Build time: ${ELAPSED}s"
echo ""
echo "Next steps:"
echo "  ./setup.sh    # Will automatically use cached images"
echo "  ./demo.sh     # Run the POC"
echo ""
echo "To rebuild cache after code changes:"
echo "  ./build-images.sh"
echo ""
