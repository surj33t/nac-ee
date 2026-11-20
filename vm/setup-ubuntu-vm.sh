#!/usr/bin/env bash
# One-time setup of the build/test VM (Ubuntu Server 24.04 LTS guest in VirtualBox).
# Works on both amd64 (Intel Mac) and arm64 (Apple Silicon Mac) guests.
#   curl/scp this file into the VM, then:  bash setup-ubuntu-vm.sh
set -euo pipefail

ANSIBLE_BUILDER_VERSION=3.2.0
ANSIBLE_NAVIGATOR_VERSION=26.11.0

echo ">> Installing podman, git, python tooling"
sudo apt-get update
sudo apt-get install -y build-essential python3-dev libonig-dev podman buildah skopeo git make jq python3-venv pipx uidmap slirp4netns fuse-overlayfs

echo ">> Rootless podman: make sure subuid/subgid ranges exist for $USER"
grep -q "^$USER:" /etc/subuid || sudo usermod --add-subuids 100000-165535 "$USER"
grep -q "^$USER:" /etc/subgid || sudo usermod --add-subgids 100000-165535 "$USER"
podman system migrate || true

echo ">> Short-name resolution so 'fedora:42' style names don't prompt"
mkdir -p ~/.config/containers
cat > ~/.config/containers/registries.conf <<'EOF'
unqualified-search-registries = ["registry.fedoraproject.org", "quay.io", "docker.io"]
short-name-mode = "permissive"
EOF

echo ">> Installing ansible-builder and ansible-navigator (pinned) with pipx"
pipx ensurepath
pipx install "ansible-builder==${ANSIBLE_BUILDER_VERSION}"
pipx install "ansible-navigator==${ANSIBLE_NAVIGATOR_VERSION}"

echo
echo "Done. Open a new shell (or 'source ~/.bashrc') so ~/.local/bin is on PATH, then:"
echo "  ansible-builder --version && ansible-navigator --version && podman info --format '{{.Host.Arch}}'"
