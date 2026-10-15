#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -summary

cert=$(echo "$built" | yq e 'select(.kind == "Certificate" and .metadata.name == "local-wildcard")' -)
[ -n "$cert" ] || { echo "FAIL: no local-wildcard Certificate found"; exit 1; }
[ "$(echo "$cert" | yq e '.metadata.namespace' -)" = "traefik" ] || { echo "FAIL: certificate must live in the traefik namespace so the TLSStore can reference its secret"; exit 1; }
[ "$(echo "$cert" | yq e '.spec.secretName' -)" = "local-wildcard-tls" ] || { echo "FAIL: certificate must target the local-wildcard-tls secret"; exit 1; }
[ "$(echo "$cert" | yq e '.spec.issuerRef.name' -)" = "letsencrypt-staging" ] || { echo "FAIL: must start on the staging issuer, not production, until verified working"; exit 1; }
dns_names=$(echo "$cert" | yq e '.spec.dnsNames | join(",")' -)
case ",$dns_names," in
  *,"*.local.fabriciooml.dev",*) ;;
  *) echo "FAIL: certificate must cover the *.local.fabriciooml.dev wildcard"; exit 1 ;;
esac

tlsstore=$(echo "$built" | yq e 'select(.kind == "TLSStore" and .metadata.name == "default")' -)
[ -n "$tlsstore" ] || { echo "FAIL: no default TLSStore found"; exit 1; }
[ "$(echo "$tlsstore" | yq e '.metadata.namespace' -)" = "traefik" ] || { echo "FAIL: TLSStore must live in the traefik namespace"; exit 1; }
[ "$(echo "$tlsstore" | yq e '.spec.defaultCertificate.secretName' -)" = "local-wildcard-tls" ] || { echo "FAIL: TLSStore must default to the wildcard cert's secret"; exit 1; }

dashboard_route=$(echo "$built" | yq e 'select(.kind == "IngressRoute" and .metadata.name == "traefik-dashboard")' -)
[ -n "$dashboard_route" ] || { echo "FAIL: no traefik-dashboard IngressRoute found"; exit 1; }
entrypoints=$(echo "$dashboard_route" | yq e '.spec.entryPoints | join(",")' -)
case ",$entrypoints," in
  *,"websecure",*) ;;
  *) echo "FAIL: dashboard route must use the websecure entrypoint, so it picks up the default tls cert"; exit 1 ;;
esac
match=$(echo "$dashboard_route" | yq e '.spec.routes[0].match' -)
case "$match" in
  *traefik.local.fabriciooml.dev*) ;;
  *) echo "FAIL: dashboard route must match the lan-only traefik hostname"; exit 1 ;;
esac

public_cert=$(echo "$built" | yq e 'select(.kind == "Certificate" and .metadata.name == "public-wildcard")' -)
[ -n "$public_cert" ] || { echo "FAIL: no public-wildcard Certificate found"; exit 1; }
[ "$(echo "$public_cert" | yq e '.metadata.namespace' -)" = "traefik" ] || { echo "FAIL: public certificate must live in the traefik namespace"; exit 1; }
[ "$(echo "$public_cert" | yq e '.spec.secretName' -)" = "public-wildcard-tls" ] || { echo "FAIL: public certificate must target the public-wildcard-tls secret"; exit 1; }
[ "$(echo "$public_cert" | yq e '.spec.issuerRef.name' -)" = "letsencrypt-staging" ] || { echo "FAIL: public certificate must also start on the staging issuer"; exit 1; }
public_dns_names=$(echo "$public_cert" | yq e '.spec.dnsNames | join(",")' -)
case ",$public_dns_names," in
  *,"*.fabriciooml.dev",*) ;;
  *) echo "FAIL: public certificate must cover the *.fabriciooml.dev wildcard"; exit 1 ;;
esac

tlsstore_certs=$(echo "$tlsstore" | yq e '.spec.certificates[].secretName' -)
case "$tlsstore_certs" in
  *public-wildcard-tls*) ;;
  *) echo "FAIL: TLSStore must also carry the public wildcard cert, so SNI picks the right one per hostname"; exit 1 ;;
esac

echo "PASS"
