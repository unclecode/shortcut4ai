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
    else
        log $RED "❌ Hammerspoon is required for this application. Aborting."
        exit 1
    fi
fi

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Create necessary directories
log $BLUE "📁 Creating directories..."
mkdir -p ~/.hammerspoon/shortcut4ai/audio

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

log $GREEN "✨ Installation complete! Please:"
log $CYAN "1. Restart Hammerspoon if it's running"
log $CYAN "2. Grant necessary permissions when prompted"
log $CYAN "3. Check the Hammerspoon menu bar icon to confirm installation"