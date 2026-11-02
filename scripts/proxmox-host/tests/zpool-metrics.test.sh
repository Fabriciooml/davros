#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../zpool-metrics.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

stub="$work/bin"
mkdir -p "$stub"
cat > "$stub/zpool" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list) printf 'tank\t1000\t600\t400\tONLINE\nslow\t500\t100\t400\tDEGRADED\n' ;;
  get)  case "${@: -1}" in tank) echo 7 ;; slow) echo 0 ;; esac ;;
esac
EOF
chmod +x "$stub/zpool"

out="$work/out"
PATH="$stub:$PATH" TEXTFILE_DIR="$out" NOW=1000 bash "$script"
prom="$out/zpool.prom"

assert() { grep -qxF "$1" "$prom" || { echo "FAIL: missing line: $1"; exit 1; }; }
assert 'homelab_zpool_size_bytes{pool="tank"} 1000'
assert 'homelab_zpool_allocated_bytes{pool="tank"} 600'
assert 'homelab_zpool_free_bytes{pool="tank"} 400'
assert 'homelab_zpool_freeing_bytes{pool="tank"} 7'
assert 'homelab_zpool_health{pool="tank",state="ONLINE"} 1'
assert 'homelab_zpool_size_bytes{pool="slow"} 500'
assert 'homelab_zpool_health{pool="slow",state="DEGRADED"} 1'
assert 'homelab_collector_last_success_timestamp_seconds{collector="zpool"} 1000'
assert '# TYPE homelab_zpool_size_bytes gauge'
[ "$(stat -c %a "$prom")" = "644" ] || { echo "FAIL: zpool.prom must be world-readable (0644) for node_exporter"; exit 1; }
[ "$(ls -A "$out")" = "zpool.prom" ] || { echo "FAIL: no temp files may be left behind"; exit 1; }

# well-formedness: node_exporter rejects the whole file on one malformed line
! grep -qF 'pool=""' "$prom" || { echo "FAIL: line with empty pool label:"; grep -nF 'pool=""' "$prom"; exit 1; }
bad=$(grep -vE '^#|^$' "$prom" | grep -vE '^[a-z_][a-z0-9_]*\{[^}]*\} [^ ]+$' || true)
[ -z "$bad" ] || { echo "FAIL: malformed sample line(s):"; echo "$bad"; exit 1; }
! grep -qx '' "$prom" || { echo "FAIL: empty line(s) in zpool.prom"; exit 1; }

# a failing zpool must leave the previous file untouched and exit non-zero
before=$(cat "$prom")
printf '#!/usr/bin/env bash\nexit 1\n' > "$stub/zpool"
if PATH="$stub:$PATH" TEXTFILE_DIR="$out" NOW=2000 bash "$script" 2>/dev/null; then
  echo "FAIL: must exit non-zero when zpool fails"; exit 1
fi
[ "$(cat "$prom")" = "$before" ] || { echo "FAIL: failed run must keep the previous metrics file"; exit 1; }
[ "$(ls -A "$out")" = "zpool.prom" ] || { echo "FAIL: failed run must not leave temp files"; exit 1; }

# cron runs with PATH=/usr/bin:/bin, so the collector must append the sbin dirs itself (append keeps test stubs first)
grep -qF 'export PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin"' "$script" || { echo "FAIL: collector must append sbin dirs to PATH for cron"; exit 1; }

echo "PASS"
