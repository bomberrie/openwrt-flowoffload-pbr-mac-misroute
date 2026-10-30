#!/usr/bin/env sh
set -eu

# Installs flow offload guard for PBR/NAT on OpenWrt (firewall4).
# Usage: ssh root@router 'sh -s' < apply.sh

RULESET="inet fw4 ft"
MARK_RULE="meta mark != 0 return"
NAT_RULE="ct status { dnat, snat } return"
NFT_INCLUDE="/etc/nftables.d/99-flowoffload-pbr.nft"

log() { echo "[mitigation] $*"; }

ensure_chain() {
  if ! nft list chain inet fw4 ft >/dev/null 2>&1; then
    echo "fw4 flowtable chain not found; is firewall4 running?" >&2
    exit 1
  fi
}

rule_absent() {
  ! nft list chain $RULESET 2>/dev/null | grep -F "$1" >/dev/null 2>&1
}

install_rule() {
  local rule="$1"
  if rule_absent "$rule"; then
    nft insert rule $RULESET $rule
    log "inserted: $rule"
  else
    log "present: $rule"
  fi
}

install_persistent_include() {
  if [ -d "/etc/nftables.d" ]; then
    cat >"$NFT_INCLUDE" <<'EOF'
table inet fw4 {
  chain ft {
    meta mark != 0 counter return
    ct status { dnat, snat } counter return
  }
}
EOF
    log "installed persistent include: $NFT_INCLUDE"
  fi
}

main() {
  ensure_chain
  install_persistent_include
  install_rule "$MARK_RULE"
  install_rule "$NAT_RULE"
  if [ -f "$NFT_INCLUDE" ] && [ -x /etc/init.d/firewall ]; then
    /etc/init.d/firewall reload || /etc/init.d/firewall restart || true
  fi
  log "mitigation active (PBR/NAT flows stay off flowtable)"
}

main "$@"
