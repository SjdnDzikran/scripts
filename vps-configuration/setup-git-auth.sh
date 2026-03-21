#!/bin/bash

# Setup SSH keys for git authentication
# Usage: ./setup-git-auth.sh [username|easypanel]
# If no argument provided, sets up for current user

TARGET_USER="${1:-$(whoami)}"

echo "Setting up SSH keys for: $TARGET_USER"

if [ "$TARGET_USER" = "easypanel" ]; then
    # Setup for EasyPanel container
    CONTAINER_ID=$(docker ps | grep easypanel | awk '{print $1}' | head -1)
    
    if [ -z "$CONTAINER_ID" ]; then
        echo "Error: EasyPanel container not found"
        exit 1
    fi
    
    echo "Found EasyPanel container: $CONTAINER_ID"
    
    # Generate keys inside container
    docker exec $CONTAINER_ID sh -c "
        mkdir -p ~/.ssh && \
        chmod 700 ~/.ssh && \
        ssh-keygen -t ed25519 -C 'easypanel@vps' -f ~/.ssh/id_ed25519 -N '' && \
        ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null
    "
    
    # Get public key
    PUBLIC_KEY=$(docker exec $CONTAINER_ID cat ~/.ssh/id_ed25519.pub)
    
    echo "=========================================="
    echo "Add this SSH key to GitHub:"
    echo "=========================================="
    echo "$PUBLIC_KEY"
    echo "=========================================="
    echo ""
    echo "After adding to GitHub, test connection:"
    echo "docker exec $CONTAINER_ID ssh -T git@github.com"
    
else
    # Setup for system user
    if ! id "$TARGET_USER" &>/dev/null; then
        echo "Error: User '$TARGET_USER' does not exist"
        echo "Create user first: sudo useradd -m $TARGET_USER"
        exit 1
    fi
    
    # Generate keys
    su - $TARGET_USER -c "
        mkdir -p ~/.ssh && \
        chmod 700 ~/.ssh && \
        ssh-keygen -t ed25519 -C '${TARGET_USER}@vps' -f ~/.ssh/id_ed25519 -N '' && \
        ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null
    "
    
    # Get public key
    PUBLIC_KEY=$(cat /home/$TARGET_USER/.ssh/id_ed25519.pub)
    if [ $? -ne 0 ]; then
        PUBLIC_KEY=$(cat /root/.ssh/id_ed25519.pub)
    fi
    
    echo "=========================================="
    echo "Add this SSH key to GitHub:"
    echo "=========================================="
    echo "$PUBLIC_KEY"
    echo "=========================================="
    echo ""
    echo "After adding to GitHub, test connection:"
    echo "su - $TARGET_USER -c 'ssh -T git@github.com'"
fi

echo ""
echo "Configure git for $TARGET_USER:"
echo "git config --global user.name \"Your Name\""
echo "git config --global user.email \"your@email.com\""