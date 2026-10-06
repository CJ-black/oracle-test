#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env was not found: $ENV_FILE"
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${COMPARTMENT_ID:?COMPARTMENT_ID is missing in .env}"
: "${REGION:?REGION is missing in .env}"
: "${OCI_CONFIG_FILE:?OCI_CONFIG_FILE is missing in .env}"
: "${OCI_PROFILE:?OCI_PROFILE is missing in .env}"
: "${VCN_NAME:?VCN_NAME is missing in .env}"
: "${SUBNET_NAME:?SUBNET_NAME is missing in .env}"
: "${GATEWAY_NAME:?GATEWAY_NAME is missing in .env}"
: "${SECURITY_LIST_NAME:?SECURITY_LIST_NAME is missing in .env}"
: "${SSH_SOURCE_CIDR:?SSH_SOURCE_CIDR is missing in .env}"
: "${VCN_CIDR_BLOCK:?VCN_CIDR_BLOCK is missing in .env}"
: "${SUBNET_CIDR_BLOCK:?SUBNET_CIDR_BLOCK is missing in .env}"
: "${VCN_DNS_LABEL:?VCN_DNS_LABEL is missing in .env}"
: "${SUBNET_DNS_LABEL:?SUBNET_DNS_LABEL is missing in .env}"

OCI_BIN="${OCI_BIN:-}"
if [[ -z "$OCI_BIN" ]]; then
  OCI_BIN="$(command -v oci 2>/dev/null || true)"
fi
if [[ -z "$OCI_BIN" && -x "/usr/local/bin/oci" ]]; then
  OCI_BIN="/usr/local/bin/oci"
fi
if [[ -z "$OCI_BIN" && -x "/opt/homebrew/bin/oci" ]]; then
  OCI_BIN="/opt/homebrew/bin/oci"
fi
if [[ -z "$OCI_BIN" ]]; then
  echo "ERROR: OCI CLI was not found."
  exit 1
fi

OCI=("$OCI_BIN" --config-file "$OCI_CONFIG_FILE" --profile "$OCI_PROFILE" --region "$REGION")

vcn_id=$("${OCI[@]}" network vcn list \
  --compartment-id "$COMPARTMENT_ID" \
  --display-name "$VCN_NAME" \
  --query 'data[0].id' --raw-output)
if [[ -z "$vcn_id" || "$vcn_id" == "null" ]]; then
  vcn_id=$("${OCI[@]}" network vcn create \
    --compartment-id "$COMPARTMENT_ID" \
    --cidr-blocks "[\"$VCN_CIDR_BLOCK\"]" \
    --display-name "$VCN_NAME" \
    --dns-label "$VCN_DNS_LABEL" \
    --wait-for-state AVAILABLE \
    --query 'data.id' --raw-output)
fi

igw_id=$("${OCI[@]}" network internet-gateway list \
  --compartment-id "$COMPARTMENT_ID" \
  --vcn-id "$vcn_id" \
  --display-name "$GATEWAY_NAME" \
  --query 'data[0].id' --raw-output)
if [[ -z "$igw_id" || "$igw_id" == "null" ]]; then
  igw_id=$("${OCI[@]}" network internet-gateway create \
    --compartment-id "$COMPARTMENT_ID" \
    --vcn-id "$vcn_id" \
    --is-enabled true \
    --display-name "$GATEWAY_NAME" \
    --wait-for-state AVAILABLE \
    --query 'data.id' --raw-output)
fi

route_table_id=$("${OCI[@]}" network vcn get \
  --vcn-id "$vcn_id" \
  --query 'data."default-route-table-id"' --raw-output)
"${OCI[@]}" network route-table update \
  --rt-id "$route_table_id" \
  --route-rules "[{\"destination\":\"0.0.0.0/0\",\"destinationType\":\"CIDR_BLOCK\",\"networkEntityId\":\"$igw_id\"}]" \
  --force >/dev/null

security_list_id=$("${OCI[@]}" network security-list list \
  --compartment-id "$COMPARTMENT_ID" \
  --vcn-id "$vcn_id" \
  --display-name "$SECURITY_LIST_NAME" \
  --query 'data[0].id' --raw-output)
if [[ -z "$security_list_id" || "$security_list_id" == "null" ]]; then
  security_list_id=$("${OCI[@]}" network security-list create \
    --compartment-id "$COMPARTMENT_ID" \
    --vcn-id "$vcn_id" \
    --display-name "$SECURITY_LIST_NAME" \
    --ingress-security-rules "[{\"source\":\"$SSH_SOURCE_CIDR\",\"protocol\":\"6\",\"tcpOptions\":{\"destinationPortRange\":{\"min\":22,\"max\":22}}}]" \
    --egress-security-rules '[{"destination":"0.0.0.0/0","protocol":"all"}]' \
    --query 'data.id' --raw-output)
else
  "${OCI[@]}" network security-list update \
    --security-list-id "$security_list_id" \
    --ingress-security-rules "[{\"source\":\"$SSH_SOURCE_CIDR\",\"protocol\":\"6\",\"tcpOptions\":{\"destinationPortRange\":{\"min\":22,\"max\":22}}}]" \
    --egress-security-rules '[{"destination":"0.0.0.0/0","protocol":"all"}]' \
    --force >/dev/null
fi

subnet_id=$("${OCI[@]}" network subnet list \
  --compartment-id "$COMPARTMENT_ID" \
  --vcn-id "$vcn_id" \
  --display-name "$SUBNET_NAME" \
  --query 'data[0].id' --raw-output)
if [[ -z "$subnet_id" || "$subnet_id" == "null" ]]; then
subnet_id=$("${OCI[@]}" network subnet create \
    --compartment-id "$COMPARTMENT_ID" \
    --vcn-id "$vcn_id" \
    --cidr-block "$SUBNET_CIDR_BLOCK" \
    --display-name "$SUBNET_NAME" \
    --dns-label "$SUBNET_DNS_LABEL" \
    --route-table-id "$route_table_id" \
    --security-list-ids "[\"$security_list_id\"]" \
    --wait-for-state AVAILABLE \
    --query 'data.id' --raw-output)
fi

printf 'VCN_ID=%s\nSUBNET_ID=%s\n' "$vcn_id" "$subnet_id"
