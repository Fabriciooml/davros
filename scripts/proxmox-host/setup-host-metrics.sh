#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
listen_addr="${LISTEN_ADDR:-192.168.31.42:9100}"
textfile_dir="${TEXTFILE_DIR:-/var/lib/prometheus/node-exporter}"
sbin_dir="${SBIN_DIR:-/usr/local/sbin}"
defaults_file="${DEFAULTS_FILE:-/etc/default/prometheus-node-exporter}"
cron_file="${CRON_FILE:-/etc/cron.d/host-metrics}"

if [ "$(id -u)" -ne 0 ]; then
  echo "run this as root on the proxmox host" >&2
  exit 1
fi

for tool in zpool smartctl lsblk flock; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool is not installed, install it before running this installer" >&2
    exit 1
  fi
done

for collector in zpool-metrics.sh smart-metrics.sh; do
  if [ ! -f "$here/$collector" ]; then
    echo "$here/$collector not found, run this installer from the repo's scripts/proxmox-host directory" >&2
    exit 1
  fi
done

want_args="ARGS=\"--web.listen-address=${listen_addr} --collector.textfile.directory=${textfile_dir}\""
changed=0
if [ "$(cat "$defaults_file" 2>/dev/null || true)" != "$want_args" ]; then
  mkdir -p "$(dirname "$defaults_file")"
  echo "$want_args" > "$defaults_file"
  changed=1
fi

# our args file is written first and kept (--force-confold), so the service never listens on 0.0.0.0
DEBIAN_FRONTEND=noninteractive apt-get --no-install-recommends -o Dpkg::Options::=--force-confold install -y prometheus-node-exporter

# restart right away so an already-running service stops listening on 0.0.0.0 before anything else can fail
systemctl enable --now prometheus-node-exporter
if [ "$changed" -eq 1 ]; then
  systemctl restart prometheus-node-exporter
fi

install -d -m 0755 "$textfile_dir" "$sbin_dir"
install -m 0755 "$here/zpool-metrics.sh" "$sbin_dir/zpool-metrics.sh"
install -m 0755 "$here/smart-metrics.sh" "$sbin_dir/smart-metrics.sh"

cron_lines="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
* * * * * root flock -n /run/zpool-metrics.lock ${sbin_dir}/zpool-metrics.sh >> /var/log/host-metrics.log 2>&1
*/10 * * * * root flock -n /run/smart-metrics.lock ${sbin_dir}/smart-metrics.sh >> /var/log/host-metrics.log 2>&1"
if [ "$(cat "$cron_file" 2>/dev/null || true)" != "$cron_lines" ]; then
  echo "$cron_lines" > "$cron_file"
  chmod 0644 "$cron_file"
fi

TEXTFILE_DIR="$textfile_dir" "$sbin_dir/zpool-metrics.sh"
TEXTFILE_DIR="$textfile_dir" "$sbin_dir/smart-metrics.sh"

echo "node_exporter configured: ${listen_addr}, textfile dir ${textfile_dir}"
cat "$cron_file"
