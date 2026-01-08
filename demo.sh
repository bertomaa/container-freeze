#!/bin/bash
# Container Freeze - Demo Runner
# Redirects to cfreeze demo command

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Note: This script is deprecated. Use 'cfreeze demo' instead."
echo ""

exec "$PROJECT_ROOT/cfreeze" demo "$@"
