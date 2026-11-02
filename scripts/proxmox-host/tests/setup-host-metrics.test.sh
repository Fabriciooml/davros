#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../setup-host-metrics.sh"
bash_bin=$(command -v bash)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
stub="$work/bin"
mkdir -p "$stub"
log="$work/calls.log"

for tool in apt-get systemctl; do
  printf '#!/usr/bin/env bash\necho "%s $*" >> "%s"\n' "$tool" "$log" > "$stub/$tool"
done
for tool in smartctl flock; do printf '#!/usr/bin/env bash\nexit 0\n' > "$stub/$tool"; done
printf '#!/usr/bin/env bash\necho "pool 1 1 1 ONLINE"\n' > "$stub/zpool"
printf '#!/usr/bin/env bash\necho "sda disk 1"\n' > "$stub/lsblk"
printf '#!/usr/bin/env bash\necho 0\n' > "$stub/id"
chmod +x "$stub"/*

run() {
  PATH="$stub:$PATH" LISTEN_ADDR=192.168.31.42:9100 TEXTFILE_DIR="$work/textfile" SBIN_DIR="$work/sbin" \
    DEFAULTS_FILE="$work/default" CRON_FILE="$work/cron" bash "$script"
}

run >/dev/null
[ "$(cat "$work/default")" = 'ARGS="--web.listen-address=192.168.31.42:9100 --collector.textfile.directory='"$work"'/textfile"' ] \
  || { echo "FAIL: args file must bind the LAN address and set the textfile directory"; cat "$work/default"; exit 1; }
case "$(cat "$work/default")" in *0.0.0.0*) echo "FAIL: must never bind 0.0.0.0"; exit 1 ;; esac
grep -q 'force-confold' "$log" || { echo "FAIL: apt-get must keep our args file (--force-confold)"; exit 1; }
grep -q -- '--no-install-recommends' "$log" || { echo "FAIL: apt-get must not pull recommended packages (node-exporter-collectors)"; exit 1; }
grep -q 'install -y prometheus-node-exporter' "$log" || { echo "FAIL: must install prometheus-node-exporter"; exit 1; }
[ -x "$work/sbin/zpool-metrics.sh" ] && [ -x "$work/sbin/smart-metrics.sh" ] || { echo "FAIL: collectors must be installed executable"; exit 1; }
grep -qF '* * * * * root flock -n /run/zpool-metrics.lock '"$work"'/sbin/zpool-metrics.sh' "$work/cron" || { echo "FAIL: zpool cron line missing"; exit 1; }
grep -qF '*/10 * * * * root flock -n /run/smart-metrics.lock '"$work"'/sbin/smart-metrics.sh' "$work/cron" || { echo "FAIL: smart cron line missing"; exit 1; }
[ "$(head -n1 "$work/cron")" = 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' ] || { echo "FAIL: cron file must start with a PATH line that includes /usr/sbin"; exit 1; }
[ -f "$work/textfile/zpool.prom" ] && [ -f "$work/textfile/smart.prom" ] || { echo "FAIL: collectors must run once at install so metrics exist immediately"; exit 1; }
grep -q 'systemctl enable --now prometheus-node-exporter' "$log" || { echo "FAIL: service must be enabled and started"; exit 1; }
grep -q 'systemctl restart prometheus-node-exporter' "$log" || { echo "FAIL: first run changes the args file, so the service must restart"; exit 1; }

: > "$log"
run >/dev/null
if grep -q 'systemctl restart' "$log"; then echo "FAIL: an unchanged second run must not restart the service"; exit 1; fi

# pre-existing service with the Debian default args must be restarted even if a later step fails
: > "$log"
printf '#!/usr/bin/env bash\nexit 1\n' > "$stub/zpool"
printf 'ARGS=""\n' > "$work/d3"
if PATH="$stub:$PATH" LISTEN_ADDR=192.168.31.42:9100 TEXTFILE_DIR="$work/t3" SBIN_DIR="$work/s3" \
  DEFAULTS_FILE="$work/d3" CRON_FILE="$work/c3" bash "$script" >/dev/null 2>&1; then
  echo "FAIL: a failing collector must make the installer exit non-zero"; exit 1
fi
grep -q 'systemctl restart prometheus-node-exporter' "$log" || { echo "FAIL: restart must happen before the collectors run, even if they fail"; exit 1; }
printf '#!/usr/bin/env bash\necho "pool 1 1 1 ONLINE"\n' > "$stub/zpool"

printf '#!/usr/bin/env bash\necho 1000\n' > "$stub/id"
if err=$(run 2>&1); then echo "FAIL: must refuse to run as non-root"; exit 1; fi
case "$err" in *"as root"*) ;; *) echo "FAIL: refusal must say to run as root, got: $err"; exit 1 ;; esac

printf '#!/usr/bin/env bash\necho 0\n' > "$stub/id"
rm "$stub/smartctl"
# PATH is only the stub dir so a real smartctl on this machine cannot satisfy the check
ln -s "$(command -v dirname)" "$stub/dirname"
ln -s "$bash_bin" "$stub/bash"   # the stubs use #!/usr/bin/env bash
if err=$(PATH="$stub" LISTEN_ADDR=x TEXTFILE_DIR="$work/t2" SBIN_DIR="$work/s2" DEFAULTS_FILE="$work/d2" CRON_FILE="$work/c2" "$bash_bin" "$script" 2>&1); then
  echo "FAIL: must refuse when smartctl is missing"; exit 1
fi
case "$err" in *smartctl*) ;; *) echo "FAIL: missing-tool refusal must name smartctl, got: $err"; exit 1 ;; esac

echo "PASS"
