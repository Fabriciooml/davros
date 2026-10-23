#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -skip Secret -summary

k=$(echo "$built" | yq e 'select(.kind == "Deployment" and .metadata.name == "kafka")' -)
[ -n "$k" ] || { echo "FAIL: no Deployment kafka"; exit 1; }
[ "$(echo "$k" | yq e '.spec.strategy.type' -)" = "Recreate" ] || { echo "FAIL: RWO volume needs Recreate"; exit 1; }
[ "$(echo "$k" | yq e '.spec.replicas' -)" = "0" ] || { echo "FAIL: kafka must stay at 0 replicas"; exit 1; }
[ "$(echo "$k" | yq e '.spec.template.spec.enableServiceLinks' -)" = "false" ] || { echo "FAIL: kafka must disable service-link env vars"; exit 1; }
case "$(echo "$k" | yq e '.spec.template.spec.containers[0].image' -)" in
  apache/kafka:3.7.0@sha256:41c20d65b0a2180b9deca056d47540771752e69fe9225d5748dd65a25a9675d7) ;;
  *) echo "FAIL: kafka must stay on 3.7.0 by digest"; exit 1 ;;
esac
kenv() { echo "$k" | yq e ".spec.template.spec.containers[0].env[] | select(.name == \"$1\") | .value" -; }
[ "$(kenv KAFKA_NODE_ID)" = "1" ] || { echo "FAIL: node id must stay 1"; exit 1; }
[ "$(kenv KAFKA_LOG_DIRS)" = "/var/lib/kafka/data" ] || { echo "FAIL: log dir must match the imported data"; exit 1; }
[ "$(kenv KAFKA_ADVERTISED_LISTENERS)" = "INTERNAL://kafka.kafka.svc.cluster.local:9092,EXTERNAL://kafka.local.fabriciooml.dev:9094" ] || { echo "FAIL: advertised listeners"; exit 1; }
[ "$(kenv KAFKA_CONTROLLER_QUORUM_VOTERS)" = "1@kafka.kafka.svc.cluster.local:9093" ] || { echo "FAIL: quorum voters"; exit 1; }
[ "$(kenv KAFKA_LOG_RETENTION_HOURS)" = "168" ] || { echo "FAIL: retention hours must stay 168"; exit 1; }
[ "$(echo "$k" | yq e '.spec.template.spec.securityContext.runAsUser' -)" = "1000" ] || { echo "FAIL: kafka must run as uid 1000"; exit 1; }
[ "$(echo "$k" | yq e '.spec.progressDeadlineSeconds' -)" = "1800" ] || { echo "FAIL: kafka progressDeadlineSeconds must be 1800"; exit 1; }
[ "$(kenv KAFKA_LISTENERS)" = "INTERNAL://0.0.0.0:9092,EXTERNAL://0.0.0.0:9094,CONTROLLER://0.0.0.0:9093" ] || { echo "FAIL: KAFKA_LISTENERS"; exit 1; }
[ "$(kenv KAFKA_LISTENER_SECURITY_PROTOCOL_MAP)" = "INTERNAL:PLAINTEXT,EXTERNAL:PLAINTEXT,CONTROLLER:PLAINTEXT" ] || { echo "FAIL: KAFKA_LISTENER_SECURITY_PROTOCOL_MAP"; exit 1; }
[ "$(kenv KAFKA_INTER_BROKER_LISTENER_NAME)" = "INTERNAL" ] || { echo "FAIL: KAFKA_INTER_BROKER_LISTENER_NAME"; exit 1; }
[ "$(kenv KAFKA_CONTROLLER_LISTENER_NAMES)" = "CONTROLLER" ] || { echo "FAIL: KAFKA_CONTROLLER_LISTENER_NAMES"; exit 1; }
[ "$(echo "$k" | yq e '.spec.template.spec.securityContext.fsGroup' -)" = "1000" ] || { echo "FAIL: appuser is uid/gid 1000"; exit 1; }

[ "$(echo "$built" | yq e 'select(.kind == "PersistentVolumeClaim" and .metadata.name == "kafka-data") | .spec.storageClassName' -)" = "local-path" ] || { echo "FAIL: kafka data on local-path"; exit 1; }

svc=$(echo "$built" | yq e 'select(.kind == "Service" and .metadata.name == "kafka")' -)
[ "$(echo "$svc" | yq e '.spec.clusterIP' -)" = "None" ] || { echo "FAIL: kafka service must be headless"; exit 1; }
[ "$(echo "$svc" | yq e '.spec.publishNotReadyAddresses' -)" = "true" ] || { echo "FAIL: controller must reach itself before ready"; exit 1; }
[ "$(echo "$built" | yq e 'select(.kind == "Service" and .metadata.name == "kafka-external") | .spec.type' -)" = "LoadBalancer" ] || { echo "FAIL: kafka-external must be a LoadBalancer"; exit 1; }

[ "$(echo "$built" | yq e 'select(.kind == "Service" and .metadata.name == "kafka-external") | .spec.ports[] | select(.targetPort == 9094) | .targetPort' -)" = "9094" ] || { echo "FAIL: kafka-external must target 9094"; exit 1; }

ui=$(echo "$built" | yq e 'select(.kind == "Deployment" and .metadata.name == "kafka-ui")' -)
[ "$(echo "$ui" | yq e '.spec.template.spec.containers[0].env[] | select(.name == "KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS") | .value' -)" = "kafka.kafka.svc.cluster.local:9092" ] || { echo "FAIL: kafka-ui bootstrap"; exit 1; }
[ "$(echo "$ui" | yq e '.spec.template.spec.containers[0].env[] | select(.name == "KAFKA_CLUSTERS_0_NAME") | .value' -)" = "local" ] || { echo "FAIL: cluster name stays local"; exit 1; }
[ "$(echo "$ui" | yq e '.spec.progressDeadlineSeconds' -)" = "1200" ] || { echo "FAIL: kafka-ui progressDeadlineSeconds must be 1200"; exit 1; }
[ "$(echo "$ui" | yq e '.spec.replicas' -)" = "0" ] || { echo "FAIL: kafka-ui must stay at 0 replicas"; exit 1; }
[ "$(echo "$ui" | yq e '.spec.template.spec.enableServiceLinks' -)" = "false" ] || { echo "FAIL: kafka-ui must disable service-link env vars"; exit 1; }
echo "$built" | yq e 'select(.kind == "IngressRoute") | .spec.routes[0].match' - | grep -q 'kafka-ui.local.fabriciooml.dev' || { echo "FAIL: kafka-ui host missing"; exit 1; }

echo "PASS"
