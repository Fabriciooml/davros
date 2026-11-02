#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../smart-metrics.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
stub="$work/bin"
mkdir -p "$stub"

cat > "$stub/lsblk" <<'EOF'
#!/usr/bin/env bash
printf 'sda disk 1\nsdb disk 0\nsdc disk 1\nsdd disk 1\nsde disk 1\nloop0 loop 0\n'
EOF

header='=== START OF READ SMART DATA SECTION ===
SMART overall-health self-assessment test result: %s

ID# ATTRIBUTE_NAME          FLAG     VALUE WORST THRESH TYPE      UPDATED  WHEN_FAILED RAW_VALUE
'
{
  printf "$header" PASSED
  echo '  5 Reallocated_Sector_Ct   0x0003   100   100   000    Pre-fail  Always       -       0'
  echo '194 Temperature_Celsius     0x0002   100   100   000    Old_age   Always       -       25'
} > "$work/sdb.txt"
{
  printf "$header" PASSED
  echo '  5 Reallocated_Sector_Ct   0x0033   200   200   140    Pre-fail  Always       -       0'
  echo '194 Temperature_Celsius     0x0022   106   099   000    Old_age   Always       -       44'
  echo '197 Current_Pending_Sector  0x0032   200   200   000    Old_age   Always       -       0'
} > "$work/sdc.txt"
{
  printf "$header" FAILED!
  echo '  5 Reallocated_Sector_Ct   0x0033   100   100   036    Pre-fail  Always       -       3'
  echo '190 Airflow_Temperature_Cel 0x0022   039   040   000    Old_age   Always       -       61 (Min/Max 20/70)'
  echo '197 Current_Pending_Sector  0x0012   100   100   000    Old_age   Always       -       8'
} > "$work/sdd.txt"
echo 'Device is in STANDBY mode, exiting...' > "$work/sda.txt"
: > "$work/sde.txt"   # open failure: no output

cat > "$stub/smartctl" <<EOF
#!/usr/bin/env bash
dev=\$(basename "\${@: -1}")
cat "$work/\$dev.txt"
EOF
chmod +x "$stub/lsblk" "$stub/smartctl"

out="$work/out"
PATH="$stub:$PATH" TEXTFILE_DIR="$out" NOW=1000 bash "$script"
prom="$out/smart.prom"

assert() { grep -qxF "$1" "$prom" || { echo "FAIL: missing line: $1"; exit 1; }; }
refute() { ! grep -qF "$1" "$prom" || { echo "FAIL: unexpected: $1"; exit 1; }; }

assert 'homelab_smart_rotational{device="sda"} 1'
assert 'homelab_smart_rotational{device="sdb"} 0'
assert 'homelab_smart_standby{device="sda"} 1'
assert 'homelab_smart_standby{device="sdb"} 0'
refute 'homelab_smart_healthy{device="sda"}'

assert 'homelab_smart_scrape_ok{device="sdb"} 1'
assert 'homelab_smart_healthy{device="sdb"} 1'
assert 'homelab_smart_reallocated_sectors{device="sdb"} 0'
assert 'homelab_smart_temperature_celsius{device="sdb"} 25'
refute 'homelab_smart_pending_sectors{device="sdb"}'   # SSD has no attribute 197

assert 'homelab_smart_pending_sectors{device="sdc"} 0'
assert 'homelab_smart_temperature_celsius{device="sdc"} 44'

assert 'homelab_smart_healthy{device="sdd"} 0'
assert 'homelab_smart_reallocated_sectors{device="sdd"} 3'
assert 'homelab_smart_pending_sectors{device="sdd"} 8'
assert 'homelab_smart_temperature_celsius{device="sdd"} 61'

assert 'homelab_smart_scrape_ok{device="sde"} 0'
refute 'homelab_smart_healthy{device="sde"}'
refute 'loop0'

assert 'homelab_collector_last_success_timestamp_seconds{collector="smart"} 1000'
[ "$(stat -c %a "$prom")" = "644" ] || { echo "FAIL: smart.prom must be 0644"; exit 1; }
[ "$(ls -A "$out")" = "smart.prom" ] || { echo "FAIL: no temp files may be left behind"; exit 1; }

# cron runs with PATH=/usr/bin:/bin, so the collector must append the sbin dirs itself (append keeps test stubs first)
grep -qF 'export PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin"' "$script" || { echo "FAIL: collector must append sbin dirs to PATH for cron"; exit 1; }

echo "PASS"
