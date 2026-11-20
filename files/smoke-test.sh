#!/usr/bin/env bash
# Runs inside the image: proves every tool and collection is present and importable.
# Usage: podman run --rm nac-ee:<tag> ee-smoke-test
set -euo pipefail
fail=0
check() { local name="$1"; shift; if out=$("$@" 2>&1); then printf '  [ok]   %-22s %s\n' "$name" "$(echo "$out" | head -1)"; else printf '  [FAIL] %-22s %s\n' "$name" "$(echo "$out" | tail -1)"; fail=1; fi; }

echo "== Binaries"
check python            python3 --version
check ansible-core      ansible --version
check ansible-runner    ansible-runner --version
check ansible-lint      ansible-lint --version
check yamllint          yamllint --version
check terraform         terraform version
check tflint            tflint --version

echo "== Python imports"
for mod in pyats genie.libs.parser pybatfish netmiko napalm scrapli ncclient pylibsshext panos infoblox_client pynetbox netaddr jmespath textfsm ttp ntc_templates; do
  check "$mod" python3 -c "import $mod; print(getattr($mod,'__version__','imported'))"
done

echo "== Collections"
for c in ansible.netcommon ansible.utils cisco.ios cisco.nxos cisco.iosxr arista.eos junipernetworks.junos paloaltonetworks.panos fortinet.fortios infoblox.nios_modules netbox.netbox community.general; do
  check "$c" bash -c "ansible-galaxy collection list $c 2>/dev/null | grep -E '^$c ' "
done

echo "== Offline playbook (localhost, ansible.utils filter)"
cat > /tmp/ee-smoke.yml <<'EOF2'
- hosts: localhost
  gather_facts: false
  tasks:
    - ansible.builtin.assert:
        that: "'10.0.0.0/24' | ansible.utils.ipaddr('network') == '10.0.0.0'"
EOF2
check playbook ansible-playbook /tmp/ee-smoke.yml

exit $fail
