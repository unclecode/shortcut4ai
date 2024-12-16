#!/bin/bash

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Helper function for colored echo
log() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

log $MAGENTA "🚀 Installing Shortcut4ai..."

# Check for Homebrew installation
if ! command_exists brew; then
    log $YELLOW "⚠️  Homebrew is not installed. It's required for installing dependencies."
    read -p "Would you like to install Homebrew? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log $CYAN "🍺 Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    else
        log $RED "❌ Homebrew is required for installation. Aborting."
        exit 1
    fi
fi

# Check for Hammerspoon installation
if ! [ -d "/Applications/Hammerspoon.app" ]; then
    log $YELLOW "⚠️  Hammerspoon is not installed."
    read -p "Would you like to install Hammerspoon? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log $CYAN "🔨 Installing Hammerspoon..."
        brew install --cask hammerspoon
        FRESH_INSTALL=true
    else
        log $RED "❌ Hammerspoon is required for this application. Aborting."
        exit 1
    fi
fi

# Install ffmpeg if not present
if ! command_exists ffmpeg; then
    log $CYAN "📦 Installing ffmpeg..."
    brew install ffmpeg
fi

# Get audio input devices
log $BLUE "🎤 Detecting audio input devices..."
# First, capture all devices, then extract only audio devices section
devices=$(ffmpeg -f avfoundation -list_devices true -i "" 2>&1 | 
    awk '/AVFoundation audio devices:/,/^[\[]?$/ { print }' | 
    grep -E "\\[[0-9]\\]" | 
    sed -E 's/.*\[([0-9]+)\](.*)/\1:\2/')

if [ -z "$devices" ]; then
    log $RED "❌ No audio devices found!"
    exit 1
fi

# Create array of devices
declare -a device_array
while IFS= read -r line; do
    # Only add non-empty lines
    if [ ! -z "$line" ]; then
        device_array+=("$line")
    fi
done <<< "$devices"

# Show devices and let user choose
log $CYAN "Available audio input devices:"
select device in "${device_array[@]}"; do
    if [ -n "$device" ]; then
        device_number=$(echo $device | cut -d':' -f1)
        device_name=$(echo $device | cut -d':' -f2- | sed 's/^ *//')
        log $GREEN "Selected device: $device_name (Device #$device_number)"
        break
    else
        log $RED "Invalid selection. Please try again."
    fi
done

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Create necessary directories
log $BLUE "📁 Creating directories..."
mkdir -p ~/.hammerspoon/shortcut4ai/audio

# Save selected device to config file
log $BLUE "💾 Saving audio device configuration..."
echo "AUDIO_DEVICE=$device_number" > ~/.hammerspoon/shortcut4ai/config
echo "AUDIO_DEVICE_NAME=$device_name" >> ~/.hammerspoon/shortcut4ai/config

# Copy files from the current directory to Hammerspoon
log $BLUE "📂 Copying files..."
cp "$SCRIPT_DIR/unified.lua" ~/.hammerspoon/shortcut4ai/
cp "$SCRIPT_DIR/grammar_prompt.md" ~/.hammerspoon/shortcut4ai/
cp "$SCRIPT_DIR/assistant_prompt.md" ~/.hammerspoon/shortcut4ai/
cp "$SCRIPT_DIR/icon.png" ~/.hammerspoon/shortcut4ai/
cp "$SCRIPT_DIR/icon@2x.png" ~/.hammerspoon/shortcut4ai/

# Create api_key file if it doesn't exist
if [ ! -f ~/.hammerspoon/shortcut4ai/.api_key ]; then
    log $BLUE "🔑 Setting up API keys..."
    
    # Check for OpenAI API key in environment
    if [ -n "$OPENAI_API_KEY" ]; then
        openai_key=$OPENAI_API_KEY
        log $GREEN "✓ Found OpenAI API key in environment variables"
    else
        read -p "Enter your OpenAI API key: " openai_key
    fi
    
    # Check for Groq API key in environment
    if [ -n "$GROQ_API_KEY" ]; then
        groq_key=$GROQ_API_KEY
        log $GREEN "✓ Found Groq API key in environment variables"
    else
        read -p "Enter your Groq API key: " groq_key
    fi
    
    echo "OPENAI_API_KEY=$openai_key" > ~/.hammerspoon/shortcut4ai/.api_key
    echo "GROQ_API_KEY=$groq_key" >> ~/.hammerspoon/shortcut4ai/.api_key
fi

# Setup init.lua
log $BLUE "⚙️  Configuring Hammerspoon..."
if [ ! -f ~/.hammerspoon/init.lua ]; then
    echo 'require("shortcut4ai/unified")' > ~/.hammerspoon/init.lua
else
    if ! grep -q 'require("shortcut4ai/unified")' ~/.hammerspoon/init.lua; then
        echo 'require("shortcut4ai/unified")' >> ~/.hammerspoon/init.lua
    fi
fi

log $GREEN "✨ Installation complete!"

# Launch Hammerspoon and guide through initial setup if needed
if [ "$FRESH_INSTALL" = true ]; then
    log $CYAN "🚀 Launching Hammerspoon for first-time setup..."
    open /Applications/Hammerspoon.app
    
    log $YELLOW "⚠️  Important: First-time Hammerspoon Setup Instructions:"
    log $CYAN "1. When Hammerspoon launches, you'll see its menu bar icon (hammer and spoon)"
    log $CYAN "2. Click the icon and select 'Preferences'"
    log $CYAN "3. In System Preferences that opens, click 'Security & Privacy'"
    log $CYAN "4. Go to 'Privacy' tab → 'Accessibility'"
    log $CYAN "5. Click the lock icon to make changes"
    log $CYAN "6. Find and check 'Hammerspoon' in the list"
    read -p "Press Enter when you've completed these steps..." -n 1 -r
    echo
    
    log $CYAN "7. Now go back to Hammerspoon menu icon"
    log $CYAN "8. Select 'Reload Config'"
else
    log $CYAN "Please:"
    log $CYAN "1. Restart Hammerspoon if it's running (click menu bar icon → 'Reload Config')"
fi

log $CYAN "Selected audio input device: $device_name"
log $CYAN "2. Grant necessary permissions when prompted"
log $CYAN "3. Check the Hammerspoon menu bar icon to confirm installation"
log $GREEN "🎉 Setup complete! Enjoy using Shortcut4ai!"