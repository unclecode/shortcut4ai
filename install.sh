#!/bin/bash

echo "Installing Shortcut4ai..."

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Create necessary directories
echo "Creating directories..."
mkdir -p ~/.hammerspoon/shortcut4ai/audio

# Copy files from the current directory to Hammerspoon
echo "Copying files..."
cp "$SCRIPT_DIR/unified.lua" ~/.hammerspoon/shortcut4ai/
cp "$SCRIPT_DIR/grammar_prompt.md" ~/.hammerspoon/shortcut4ai/
cp "$SCRIPT_DIR/assistant_prompt.md" ~/.hammerspoon/shortcut4ai/
cp "$SCRIPT_DIR/icon.png" ~/.hammerspoon/shortcut4ai/
cp "$SCRIPT_DIR/icon@2x.png" ~/.hammerspoon/shortcut4ai/

# Create api_key file if it doesn't exist
if [ ! -f ~/.hammerspoon/shortcut4ai/.api_key ]; then
    echo "Setting up API keys..."
    
    # Check for OpenAI API key in environment
    if [ -n "$OPENAI_API_KEY" ]; then
        openai_key=$OPENAI_API_KEY
        echo "Found OpenAI API key in environment variables"
    else
        read -p "Enter your OpenAI API key: " openai_key
    fi
    
    # Check for Groq API key in environment
    if [ -n "$GROQ_API_KEY" ]; then
        groq_key=$GROQ_API_KEY
        echo "Found Groq API key in environment variables"
    else
        read -p "Enter your Groq API key: " groq_key
    fi
    
    echo "OPENAI_API_KEY=$openai_key" > ~/.hammerspoon/shortcut4ai/.api_key
    echo "GROQ_API_KEY=$groq_key" >> ~/.hammerspoon/shortcut4ai/.api_key
fi

# Setup init.lua
echo "Configuring Hammerspoon..."
if [ ! -f ~/.hammerspoon/init.lua ]; then
    echo 'require("shortcut4ai/unified")' > ~/.hammerspoon/init.lua
else
    if ! grep -q 'require("shortcut4ai/unified")' ~/.hammerspoon/init.lua; then
        echo 'require("shortcut4ai/unified")' >> ~/.hammerspoon/init.lua
    fi
fi

echo "Installation complete! Please:"
echo "1. Restart Hammerspoon if it's running"
echo "2. Grant necessary permissions when prompted"
echo "3. Check the Hammerspoon menu bar icon to confirm installation"