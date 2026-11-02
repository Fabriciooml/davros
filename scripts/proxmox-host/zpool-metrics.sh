#!/usr/bin/env bash
set -euo pipefail
export PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin"

out_dir="${TEXTFILE_DIR:-/var/lib/prometheus/node-exporter}"
now="${NOW:-$(date +%s)}"

mkdir -p "$out_dir"
tmp=$(mktemp "$out_dir/.zpool.XXXXXX")
trap 'rm -f "$tmp"' EXIT

list=$(zpool list -Hp -o name,size,allocated,free,health)

freeing=""
while read -r name _; do
  value=$(zpool get -Hp -o value freeing "$name")
  freeing+="$name $value"$'\n'
done <<<"$list"

emit() { # metric, help, awk field holding the value, input rows
  printf '# HELP %s %s\n# TYPE %s gauge\n' "$1" "$2" "$1"
  awk -v m="$1" -v f="$3" 'NF {printf "%s{pool=\"%s\"} %s\n", m, $1, $f}' <<<"$4"
}

{
  emit homelab_zpool_size_bytes "Total size of the pool." 2 "$list"
  emit homelab_zpool_allocated_bytes "Allocated bytes in the pool." 3 "$list"
  emit homelab_zpool_free_bytes "Free bytes in the pool." 4 "$list"
  emit homelab_zpool_freeing_bytes "Bytes still being released by an asynchronous destroy." 2 "$freeing"
  printf '# HELP homelab_zpool_health Pool health state, value 1 for the current state.\n# TYPE homelab_zpool_health gauge\n'
  awk '{printf "homelab_zpool_health{pool=\"%s\",state=\"%s\"} 1\n", $1, $5}' <<<"$list"
  printf '# HELP homelab_collector_last_success_timestamp_seconds Unix time of the last successful run.\n# TYPE homelab_collector_last_success_timestamp_seconds gauge\n'
  printf 'homelab_collector_last_success_timestamp_seconds{collector="zpool"} %s\n' "$now"
} > "$tmp"

chmod 0644 "$tmp"
mv "$tmp" "$out_dir/zpool.prom"
