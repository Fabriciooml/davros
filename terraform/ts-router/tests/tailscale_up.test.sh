#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

# fake ssh: record argv and stdin so the test can see where the key went
cat > "$workdir/ssh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_SSH_ARGS"
cat > "$FAKE_SSH_STDIN"
EOF
chmod +x "$workdir/ssh"

export FAKE_SSH_ARGS="$workdir/args" FAKE_SSH_STDIN="$workdir/stdin"
export PATH="$workdir:$PATH"

# fails without a key
if env -u TS_AUTHKEY ./scripts/tailscale-up.sh 192.168.31.42 241 192.168.31.0/24 ts-router 2>"$workdir/err"; then
  echo "FAIL: script must refuse to run without TS_AUTHKEY"; exit 1
fi
grep -q "TS_AUTHKEY" "$workdir/err" || { echo "FAIL: error message must name TS_AUTHKEY"; exit 1; }

# key goes over stdin, never argv
TS_AUTHKEY="tskey-auth-secret123" ./scripts/tailscale-up.sh 192.168.31.42 241 192.168.31.0/24 ts-router

grep -q "tskey-auth-secret123" "$FAKE_SSH_STDIN" || { echo "FAIL: key must be sent on stdin"; exit 1; }
grep -q "tskey-auth-secret123" "$FAKE_SSH_ARGS" && { echo "FAIL: key must not appear in ssh arguments"; exit 1; }
grep -q "root@192.168.31.42" "$FAKE_SSH_ARGS" || { echo "FAIL: must ssh to root@proxmox_host"; exit 1; }
grep -q -- "--advertise-routes=192.168.31.0/24" "$FAKE_SSH_ARGS" || { echo "FAIL: route not advertised"; exit 1; }
grep -q -- "--accept-dns=false" "$FAKE_SSH_ARGS" || { echo "FAIL: router must keep Pi-hole DNS (--accept-dns=false)"; exit 1; }
grep -q "pct exec 241" "$FAKE_SSH_ARGS" || { echo "FAIL: must run inside the container"; exit 1; }

# no auth key plumbing may leak into tofu config
if grep -n -i "authkey" main.tf variables.tf outputs.tf terraform.tfvars.example 2>/dev/null; then
  echo "FAIL: auth key must not appear in tofu config"; exit 1
fi

echo "PASS"
