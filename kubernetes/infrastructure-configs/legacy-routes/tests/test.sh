#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -summary

transport=$(echo "$built" | yq e 'select(.kind == "ServersTransport" and .metadata.name == "insecure-skip-verify")' -)
[ -n "$transport" ] || { echo "FAIL: insecure-skip-verify ServersTransport missing"; exit 1; }
[ "$(echo "$transport" | yq e '.spec.insecureSkipVerify' -)" = "true" ] || { echo "FAIL: ServersTransport must skip verify for self-signed backends"; exit 1; }

# name host ip port scheme
check() {
  local name=$1 host=$2 ip=$3 port=$4 scheme=$5

  local route svc slice
  route=$(echo "$built" | yq e "select(.kind == \"IngressRoute\" and .metadata.name == \"$name\")" -)
  [ -n "$route" ] || { echo "FAIL: $name IngressRoute missing"; exit 1; }
  [ "$(echo "$route" | yq e '.metadata.namespace' -)" = "legacy-routes" ] || { echo "FAIL: $name route must live in legacy-routes"; exit 1; }
  [ "$(echo "$route" | yq e '.spec.entryPoints | join(",")' -)" = "websecure" ] || { echo "FAIL: $name route must use websecure"; exit 1; }
  [ "$(echo "$route" | yq e '.spec.routes[0].match' -)" = "Host(\`$host\`)" ] || { echo "FAIL: $name route must match $host"; exit 1; }
  [ "$(echo "$route" | yq e '.spec.routes[0].services[0].name' -)" = "$name" ] || { echo "FAIL: $name route must target service $name"; exit 1; }
  [ "$(echo "$route" | yq e '.spec.routes[0].services[0].port' -)" = "$port" ] || { echo "FAIL: $name route must target port $port"; exit 1; }
  [ "$(echo "$route" | yq e '.spec.tls | has("secretName")' -)" = "false" ] || { echo "FAIL: $name route must use the default TLSStore"; exit 1; }

  if [ "$scheme" = "https" ]; then
    [ "$(echo "$route" | yq e '.spec.routes[0].services[0].scheme' -)" = "https" ] || { echo "FAIL: $name route must use scheme https"; exit 1; }
    [ "$(echo "$route" | yq e '.spec.routes[0].services[0].serversTransport' -)" = "insecure-skip-verify" ] || { echo "FAIL: $name route must use the insecure-skip-verify transport"; exit 1; }
  else
    [ "$(echo "$route" | yq e '.spec.routes[0].services[0].scheme // "http"' -)" = "http" ] || { echo "FAIL: $name route must use plain http"; exit 1; }
  fi

  svc=$(echo "$built" | yq e "select(.kind == \"Service\" and .metadata.name == \"$name\")" -)
  [ -n "$svc" ] || { echo "FAIL: $name Service missing"; exit 1; }
  [ "$(echo "$svc" | yq e '.spec | has("selector")' -)" = "false" ] || { echo "FAIL: $name Service must have no selector"; exit 1; }
  [ "$(echo "$svc" | yq e '.spec.ports[0].port' -)" = "$port" ] || { echo "FAIL: $name Service port must be $port"; exit 1; }

  slice=$(echo "$built" | yq e "select(.kind == \"EndpointSlice\" and .metadata.name == \"$name\")" -)
  [ -n "$slice" ] || { echo "FAIL: $name EndpointSlice missing"; exit 1; }
  [ "$(echo "$slice" | yq e '.metadata.labels."kubernetes.io/service-name"' -)" = "$name" ] || { echo "FAIL: $name EndpointSlice must be labelled for its Service"; exit 1; }
  [ "$(echo "$slice" | yq e '.endpoints[0].addresses[0]' -)" = "$ip" ] || { echo "FAIL: $name must point at $ip"; exit 1; }
  [ "$(echo "$slice" | yq e '.ports[0].port' -)" = "$port" ] || { echo "FAIL: $name EndpointSlice port must be $port"; exit 1; }
}

d=local.fabriciooml.dev
check qbittorrent "torrent.$d"    192.168.31.226 4242  http
check radarr      "radarr.$d"     192.168.31.226 7878  http
check sonarr      "sonarr.$d"     192.168.31.226 8989  http
check bazarr      "bazarr.$d"     192.168.31.226 6767  http
check portainer   "docker.$d"     192.168.31.226 9443  https
check haos        "haos.$d"       192.168.31.128 8123  http
check plex        "plex.$d"       192.168.31.83  32400 http
check jellyfin    "jellyfin.$d"   192.168.31.40  8096  http
check proxmox     "proxmox.$d"    192.168.31.42  8006  https
check vaultwarden "vault.$d"      192.168.31.108 8000  https
check pihole      "pihole.$d"     192.168.31.152 80    http

echo "PASS"
