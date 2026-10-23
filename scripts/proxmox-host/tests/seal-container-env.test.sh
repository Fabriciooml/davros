#!/usr/bin/env bash
set -euo pipefail

script="$(cd "$(dirname "$0")/.." && pwd)/seal-container-env.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/tmp"

# Stubs record argv (one arg per line) and are steered through env vars.
cat > "$work/bin/ssh" <<'EOF2'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$STUB_DIR/ssh.args"
if [ -n "${STUB_ENV_JSON+x}" ]; then
  echo "$STUB_ENV_JSON"
else
  echo '["PATH=/usr/bin","DATABASE_URL=postgresql://u:s3cr3t@h/d","FLAG=a b"]'
fi
EOF2
cat > "$work/bin/sops" <<'EOF2'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$STUB_DIR/sops.args"
[ "${SOPS_FAIL:-0}" = 1 ] && exit 1
for last; do :; done
cat "$last"
EOF2
chmod +x "$work/bin/ssh" "$work/bin/sops"
export STUB_DIR="$work"

run() { PATH="$work/bin:$PATH" TMPDIR="$work/tmp" bash "$script" "$@"; }

out="$work/app.sops.yaml"
stdout=$(run web ns my-secret "$out" DATABASE_URL FLAG 2>"$work/stderr")

grep -q '^  name: my-secret$' "$out" || { echo "FAIL: secret name missing"; exit 1; }
grep -q '^  namespace: ns$' "$out" || { echo "FAIL: namespace missing"; exit 1; }
grep -q 'DATABASE_URL: "postgresql://u:s3cr3t@h/d"' "$out" || { echo "FAIL: key not written"; exit 1; }
grep -q 'FLAG: "a b"' "$out" || { echo "FAIL: value with space not quoted"; exit 1; }
if grep -q 'PATH' "$out"; then echo "FAIL: unrequested key leaked"; exit 1; fi
if echo "$stdout" | grep -q 's3cr3t'; then echo "FAIL: secret value printed to stdout"; exit 1; fi
if grep -q 's3cr3t' "$work/stderr"; then echo "FAIL: secret value printed to stderr"; exit 1; fi
[ -z "$(ls -A "$work/tmp")" ] || { echo "FAIL: temp plaintext left behind"; exit 1; }
[ "$(ls "$work" | grep -c 'tmp\.')" = 0 ] || { echo "FAIL: output temp file left behind"; exit 1; }

# sops argv
sargs=$(cat "$work/sops.args")
arg_after() { echo "$sargs" | grep -x -A1 -- "$1" | sed -n 2p; }
[ "$(arg_after --encrypted-regex)" = '^(data|stringData)$' ] || { echo "FAIL: sops --encrypted-regex"; exit 1; }
[ "$(arg_after --filename-override)" = "$out" ] || { echo "FAIL: sops --filename-override"; exit 1; }
[ "$(arg_after --input-type)" = "yaml" ] || { echo "FAIL: sops --input-type"; exit 1; }
[ "$(arg_after --output-type)" = "yaml" ] || { echo "FAIL: sops --output-type"; exit 1; }

# ssh argv carries the container name in the docker inspect command
grep -q 'docker inspect web ' "$work/ssh.args" || { echo "FAIL: container name not in docker inspect command"; exit 1; }

# missing key
if run web ns my-secret "$work/x.sops.yaml" NOPE 2>"$work/err"; then
  echo "FAIL: missing key must fail"; exit 1
fi
grep -q 'missing env keys' "$work/err" || { echo "FAIL: missing key message"; exit 1; }
[ ! -s "$work/x.sops.yaml" ] || { echo "FAIL: output written despite missing key"; exit 1; }

# null env -> clean error, no traceback
if STUB_ENV_JSON=null run web ns my-secret "$work/n.sops.yaml" FOO 2>"$work/err"; then
  echo "FAIL: null env must fail"; exit 1
fi
grep -q 'missing env keys' "$work/err" || { echo "FAIL: null env must give missing env keys message"; exit 1; }
if grep -q 'Traceback' "$work/err"; then echo "FAIL: null env raised a traceback"; exit 1; fi

# bad container name: rejected before any ssh call
rm -f "$work/ssh.args"
if run 'a;b' ns my-secret "$work/y.sops.yaml" FOO 2>"$work/err"; then
  echo "FAIL: bad container name must fail"; exit 1
fi
[ ! -e "$work/ssh.args" ] || { echo "FAIL: ssh called despite bad container name"; exit 1; }
if run web ns my-secret "$work/y.sops.yaml" 'BAD-KEY' 2>"$work/err"; then
  echo "FAIL: bad env key must fail"; exit 1
fi
[ ! -e "$work/ssh.args" ] || { echo "FAIL: ssh called despite bad env key"; exit 1; }

# sops failure: no empty/partial output, no leftover temp file
fout="$work/f.sops.yaml"
if SOPS_FAIL=1 run web ns my-secret "$fout" DATABASE_URL 2>/dev/null; then
  echo "FAIL: sops failure must fail the script"; exit 1
fi
[ ! -e "$fout" ] || { echo "FAIL: output exists after sops failure"; exit 1; }
[ "$(ls "$work" | grep -c 'f\.sops\.yaml\.tmp')" = 0 ] || { echo "FAIL: temp output left after sops failure"; exit 1; }

echo "PASS"
