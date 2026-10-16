#!/usr/bin/env bash
set -euo pipefail

new_ip="$1"
sed "s/127\.0\.0\.1/${new_ip}/"
