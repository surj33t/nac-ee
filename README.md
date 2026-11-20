# nac-ee - Network as Code execution environment

One versioned container image that every NaC job runs in: Ansible, network collections, Terraform, pyATS/Genie, the Batfish client and linters, all pinned.

## What's in it (2026.11.0)

| Layer | Pinned versions |
|---|---|
| Base | Fedora 42 (Python 3.13) |
| Ansible | ansible-core 2.22.0, ansible-runner 2.4.3 |
| Collections | ansible.netcommon 8.8.0, ansible.utils 6.1.1, ansible.posix 2.2.2, community.general 14.0.1, cisco.ios 11.7.0, cisco.nxos 14.0.0, cisco.iosxr 13.0.1, arista.eos 12.3.0, junipernetworks.junos 11.0.0, paloaltonetworks.panos 3.4.2, fortinet.fortios 2.6.0, infoblox.nios_modules 1.10.0, netbox.netbox 3.24.0 |
| Testing | pyATS/Genie 26.10, pybatfish 2026.9.17.3748, netmiko 4.8.0, napalm 5.2.0, scrapli 2026.11.12, pytest 9.2.0 |
| IaC | Terraform 1.17.2, TFLint 0.66.0 (checksum-verified downloads) |
| Linters | ansible-lint 26.11.0, yamllint 1.38.0, tflint |

Full resolved lock (including transitive Python deps) is baked into the image at `/opt/ee-manifest/` and copied to `manifests/<version>/` by `build.sh`.

## Layout

```
execution-environment.yml   ansible-builder v3 definition (base image, core, build steps)
dependencies/requirements.yml   collections (exact versions)
dependencies/requirements.txt   Python packages (exact versions)
dependencies/bindep.txt         OS packages
files/smoke-test.sh             baked in as `ee-smoke-test`
build.sh                        build + smoke test + manifest + optional push
vm/setup-ubuntu-vm.sh           one-time VM setup (podman, ansible-builder, navigator)
ansible-navigator.yml           sample config for playbook repos
.github/workflows/build-ee.yml  CI: build amd64+arm64, test, push to GHCR
VERSION                         image version (CalVer: YYYY.MM.patch)
```

## 1. Create the VirtualBox VM on your Mac

**Check your chip first** (Apple menu > About This Mac):

- **Apple Silicon (M1-M4):** use VirtualBox 7.1 or newer and the **Ubuntu Server 24.04 LTS ARM64** ISO. The image you build will be `arm64`.
- **Intel:** use the **Ubuntu Server 24.04 LTS amd64** ISO. The image will be `amd64` - same arch as GitHub runners.

VM settings:

| Setting | Value |
|---|---|
| CPUs | 4 |
| RAM | 8 GB (pyATS/Genie + compile steps need it) |
| Disk | 60 GB dynamically allocated (images are ~2-3 GB, build cache grows) |
| Network | Adapter 1: NAT, with port forward Host 2222 -> Guest 22 (SSH). Add Adapter 2: Bridged if the VM needs to reach lab devices directly. |

During Ubuntu install tick **Install OpenSSH server**. Then from the Mac:

```bash
ssh -p 2222 <you>@127.0.0.1
```

## 2. Prepare the VM (once)

Copy this folder into the VM (or push it to a Git repo and clone it there):

```bash
# from the Mac
scp -P 2222 -r nac-ee <you>@127.0.0.1:~
# in the VM
cd ~/nac-ee && bash vm/setup-ubuntu-vm.sh && exec bash -l
ansible-builder --version        # 3.2.0
podman info --format '{{.Host.Arch}}'
```

## 3. Build and test

```bash
cd ~/nac-ee
chmod +x build.sh
./build.sh
```

First build takes 10-20 minutes (pip compiles a few packages). Expect the smoke test to print `[ok]` for every binary, Python import and collection, then run an offline playbook.

Poke around inside:

```bash
podman run --rm -it nac-ee:2026.11.0 bash
ansible-galaxy collection list
cat /opt/ee-manifest/tools.txt
```

## 4. Push to a registry

**GitHub Container Registry** - create a classic PAT with `write:packages`, then:

```bash
echo "$GHCR_PAT" | podman login ghcr.io -u <github-user> --password-stdin
REGISTRY=ghcr.io/<github-user-or-org> ./build.sh push
```

**Azure Container Registry** instead:

```bash
az acr login --name <acrname> --expose-token   # or: podman login <acrname>.azurecr.io
REGISTRY=<acrname>.azurecr.io ./build.sh push
```

For the CI workflow with ACR, swap the GHCR login step for `azure/login` + `az acr login`, and change `IMAGE` to `<acrname>.azurecr.io/nac-ee`.

A local push is single-arch. The **release tag should come from CI**, which builds `linux/amd64` and `linux/arm64` into one multi-arch tag, so the same tag works in pipelines and on an Apple Silicon VM.

## 5. CI release flow

1. Change a pin in `dependencies/` or `execution-environment.yml`, bump `VERSION`, open a PR - CI builds amd64 and runs the smoke test.
2. Merge to `main` - CI pushes `:<VERSION>-<sha>` and `:latest-main` (for testing).
3. Tag `v<VERSION>` - CI pushes the immutable release tag `:<VERSION>`.
4. Pipelines and `ansible-navigator.yml` reference the release tag only. Never re-push an existing release tag; cut a new version.

Using it as the job image in GitHub Actions:

```yaml
jobs:
  validate:
    runs-on: ubuntu-24.04
    container: ghcr.io/<org>/nac-ee:2026.11.0
    steps:
      - uses: actions/checkout@v4
      - run: yamllint . && ansible-lint && terraform fmt -check -recursive
```

## Batfish

The image has the **client** (`pybatfish`). Run the server as its own container next to it, in the VM:

```bash
podman run -d --name batfish -p 9996:9996 -p 9997:9997 docker.io/batfish/allinone
```

Check the Batfish image supports your VM's architecture (`podman image inspect`); on Apple Silicon, if no arm64 build is available, run Batfish in CI or on an amd64 host instead.

## Updating pins

```bash
pip index versions <package>             # latest on PyPI
ansible-galaxy collection list <name>    # inside the image
```

After any bump, diff `manifests/<old>/pip-freeze.txt` against the new one to see transitive changes before releasing.
