#!/bin/bash
# =============================================================================
# SSH Key Setup Script for GitHub (Dev Container / Ubuntu)
# Asks for email + custom key name (default: id_ed25519)
# =============================================================================

echo -e "\n🔑 SSH Key Setup for GitHub\n"

# 1. Ask for email
read -rp "Enter your email address (used as comment in the SSH key): " user_email
if [ -z "$user_email" ]; then
    echo "❌ Email cannot be empty. Exiting."
    exit 1
fi

# 2. Ask for key name (filename)
read -rp "Enter SSH key name [default: id_ed25519]: " key_name
key_name="${key_name:-id_ed25519}"

# Validate key name (basic check)
if [[ ! "$key_name" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo "❌ Invalid key name. Only letters, numbers, dots, underscores and hyphens allowed."
    exit 1
fi

# Create .ssh directory
mkdir -p ~/.ssh
chmod 700 ~/.ssh

KEY_FILE="$HOME/.ssh/$key_name"
PUB_KEY_FILE="${KEY_FILE}.pub"

echo "Using key file: $KEY_FILE"

# 3. Check if key already exists
if [ -f "$KEY_FILE" ]; then
    echo "✅ SSH key already exists at $KEY_FILE"
    read -rp "   Generate a NEW key and overwrite? (y/N): " overwrite
    if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
        echo "Skipping key generation. Using existing key."
    else
        rm -f "$KEY_FILE" "$PUB_KEY_FILE"
        echo "🗑️  Old key removed."
    fi
fi

# 4. Generate new key if needed
if [ ! -f "$KEY_FILE" ]; then
    echo "🔨 Generating new ed25519 SSH key..."
    ssh-keygen -t ed25519 -C "$user_email" -f "$KEY_FILE" -N "" -q
    echo "✅ Key generated successfully!"
else
    echo "✅ Using existing key."
fi

# 5. Start ssh-agent and add the key
echo "🚀 Starting SSH agent and adding key..."
eval "$(ssh-agent -s)" >/dev/null 2>&1
ssh-add "$KEY_FILE" 2>/dev/null

if [ $? -eq 0 ]; then
    echo "✅ Key successfully added to SSH agent"
else
    echo "⚠️  Could not add key to agent (it may already be loaded)"
fi

# 6. Show the public key
echo -e "\n📋 === COPY THIS PUBLIC KEY TO GITHUB ===\n"
cat "$PUB_KEY_FILE"
echo -e "\n✅ Paste the key above into GitHub → Settings → SSH and GPG keys → New SSH key"

# Final instructions
echo -e "\n🔍 After adding the key to GitHub, test it with:"
echo -e "   ssh -T git@github.com\n"

if [ "$key_name" != "id_ed25519" ]; then
    echo -e "⚠️  Note: You chose a custom key name ($key_name)."
    echo -e "   Git will automatically use it in most cases, but if you ever get"
    echo -e "   permission errors, you can add this to ~/.ssh/config:"
    echo -e "   Host github.com"
    echo -e "       IdentityFile ~/.ssh/$key_name"
fi

echo -e "\n🎉 Done! You can now run: git push -f origin main"