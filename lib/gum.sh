#!/bin/bash
# Container Freeze - Gum UI helpers
# Interactive CLI components using charmbracelet/gum

# Check if gum is installed
check_gum_installed() {
    if ! command -v gum &> /dev/null; then
        echo "Error: gum is required for interactive mode"
        echo ""
        echo "Install gum:"
        echo "  brew install gum                    # macOS"
        echo "  sudo pacman -S gum                  # Arch"
        echo "  sudo apt install gum                # Debian/Ubuntu (if available)"
        echo "  go install github.com/charmbracelet/gum@latest  # Go"
        echo ""
        echo "Or download from: https://github.com/charmbracelet/gum/releases"
        exit 1
    fi
}

# Print the main banner
print_banner() {
    gum style \
        --foreground 14 \
        --margin "1 0" \
'              ·  ❄  ·     ·  ❄  ·     ·  ❄  ·

  ██████╗███████╗██████╗ ███████╗███████╗███████╗███████╗
 ██╔════╝██╔════╝██╔══██╗██╔════╝██╔════╝╚══███╔╝██╔════╝
 ██║     █████╗  ██████╔╝█████╗  █████╗    ███╔╝ █████╗
 ██║     ██╔══╝  ██╔══██╗██╔══╝  ██╔══╝   ███╔╝  ██╔══╝
 ╚██████╗██║     ██║  ██║███████╗███████╗███████╗███████╗
  ╚═════╝╚═╝     ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝╚══════╝

              ·  ❄  ·     ·  ❄  ·     ·  ❄  ·'
    gum style \
        --foreground 7 \
        --align center \
        --width 60 \
        "They're Inside. Now What?"
}

# Print a styled header
print_header() {
    local title="$1"
    gum style \
        --border rounded \
        --border-foreground 6 \
        --padding "0 2" \
        --margin "1 0" \
        "$title"
}

# Print a step message
print_step() {
    gum style --foreground 12 "▶ $1"
}

# Print success message
print_success() {
    gum style --foreground 2 "✓ $1"
}

# Print warning message
print_warning() {
    gum style --foreground 3 "⚠ $1"
}

# Print error message
print_error() {
    gum style --foreground 1 "✗ $1"
}

# Confirm action with user
gum_confirm() {
    local prompt="$1"
    gum confirm "$prompt"
}

# Show a spinner while running a command
gum_spin() {
    local title="$1"
    shift
    gum spin --spinner dot --title "$title" -- "$@"
}

# Display paged content
gum_pager() {
    gum pager
}

# Format a demo for display in menu
format_demo_choice() {
    local name="$1"
    local description="$2"
    echo "$name|$description"
}
