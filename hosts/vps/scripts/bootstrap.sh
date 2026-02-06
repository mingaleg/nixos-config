#!/usr/bin/env bash
set -e

# Create mingaleg user if it doesn't exist
if ! id mingaleg &>/dev/null; then
    useradd -m -G wheel mingaleg
fi

# Set up SSH directory and authorized keys
mkdir -p /home/mingaleg/.ssh
cat > /home/mingaleg/.ssh/authorized_keys <<'EOF'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOdGlOYUp5OVA31vFPBYtMRZwbqFqFNOuv2JN3mwDZcc mingaleg@mingapred
EOF

chmod 700 /home/mingaleg/.ssh
chmod 600 /home/mingaleg/.ssh/authorized_keys
chown -R mingaleg:users /home/mingaleg/.ssh

# Allow wheel group to use sudo without password
echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel

echo "Bootstrap script completed successfully"
