#!/usr/bin/env bash
set -euo pipefail
export PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin"

out_dir="${TEXTFILE_DIR:-/var/lib/prometheus/node-exporter}"
now="${NOW:-$(date +%s)}"

mkdir -p "$out_dir"
tmp=$(mktemp "$out_dir/.smart.XXXXXX")
trap 'rm -f "$tmp"' EXIT

m_rotational="" m_standby="" m_ok="" m_healthy="" m_realloc="" m_pending="" m_temp=""
nl=$'\n'

disks=$(lsblk -dno NAME,TYPE,ROTA | awk '$2 == "disk" {print $1, $3}')

while read -r name rota; do
  [ -n "$name" ] || continue
  label="device=\"$name\""
  m_rotational+="homelab_smart_rotational{$label} $rota$nl"

  report=$(smartctl -n standby -H -A "/dev/$name" 2>&1 || true)

  if grep -q 'Device is in .* mode' <<<"$report"; then
    m_standby+="homelab_smart_standby{$label} 1$nl"
    continue
  fi
  m_standby+="homelab_smart_standby{$label} 0$nl"

  health_line=$(grep 'overall-health self-assessment test result' <<<"$report" || true)
  if [ -z "$health_line" ]; then
    m_ok+="homelab_smart_scrape_ok{$label} 0$nl"
    continue
  fi
  m_ok+="homelab_smart_scrape_ok{$label} 1$nl"

  case "$health_line" in
    *PASSED*) m_healthy+="homelab_smart_healthy{$label} 1$nl" ;;
    *)        m_healthy+="homelab_smart_healthy{$label} 0$nl" ;;
  esac

  realloc=$(awk '$1 == 5 {print $10; exit}' <<<"$report")
  pending=$(awk '$1 == 197 {print $10; exit}' <<<"$report")
  temp=$(awk '$1 == 194 || $1 == 190 {print $10; exit}' <<<"$report")
  [[ "$realloc" =~ ^[0-9]+$ ]] && m_realloc+="homelab_smart_reallocated_sectors{$label} $realloc$nl"
  [[ "$pending" =~ ^[0-9]+$ ]] && m_pending+="homelab_smart_pending_sectors{$label} $pending$nl"
  [[ "$temp" =~ ^[0-9]+$ ]] && m_temp+="homelab_smart_temperature_celsius{$label} $temp$nl"
done <<<"$disks"

section() { # metric, help, rows
  [ -n "$3" ] || return 0
  printf '# HELP %s %s\n# TYPE %s gauge\n%s' "$1" "$2" "$1" "$3"
}

{
  section homelab_smart_rotational "1 for a spinning disk, 0 for an SSD." "$m_rotational"
  section homelab_smart_standby "1 when the disk was in standby and was not woken." "$m_standby"
  section homelab_smart_scrape_ok "1 when smartctl returned a health result." "$m_ok"
  section homelab_smart_healthy "1 when the SMART overall health test passed." "$m_healthy"
  section homelab_smart_reallocated_sectors "Raw value of attribute 5." "$m_realloc"
  section homelab_smart_pending_sectors "Raw value of attribute 197." "$m_pending"
  section homelab_smart_temperature_celsius "Raw value of attribute 194 or 190." "$m_temp"
  printf '# HELP homelab_collector_last_success_timestamp_seconds Unix time of the last successful run.\n# TYPE homelab_collector_last_success_timestamp_seconds gauge\n'
  printf 'homelab_collector_last_success_timestamp_seconds{collector="smart"} %s\n' "$now"
} > "$tmp"

chmod 0644 "$tmp"
mv "$tmp" "$out_dir/smart.prom"
