#!/usr/bin/env sh
set -eu

# Removes flow offload guard rules added by mitigation/apply.sh

RULESET="inet fw4 ft"
MARK_RULE="meta mark != 0 return"
NAT_RULE="ct status { dnat, snat } return"
NFT_INCLUDE="/etc/nftables.d/99-flowoffload-pbr.nft"

log() { echo "[rollback] $*"; }

remove_rule() {
  local rule="$1"
  local handle
  handle=$(nft -a list chain $RULESET 2>/dev/null | grep -F "$rule" | sed -n 's/.*handle \([0-9]\+\).*/\1/p' | head -n1)
  while [ -n "$handle" ]; do
    nft delete rule $RULESET handle "$handle"
    log "removed: $rule (handle $handle)"
    handle=$(nft -a list chain $RULESET 2>/dev/null | grep -F "$rule" | sed -n 's/.*handle \([0-9]\+\).*/\1/p' | head -n1)
  done
}

remove_persistent_include() {
  if [ -f "$NFT_INCLUDE" ]; then
    rm -f "$NFT_INCLUDE"
    log "removed persistent include: $NFT_INCLUDE"
  fi
}

main() {
  remove_persistent_include
  if nft list chain inet fw4 ft >/dev/null 2>&1; then
    remove_rule "$MARK_RULE"
    remove_rule "$NAT_RULE"
  else
    log "fw4 ft chain missing; skipped rule removal"
  fi

  if [ -x /etc/init.d/firewall ]; then
    /etc/init.d/firewall reload || /etc/init.d/firewall restart || true
  fi
  log "rollback complete"
}

main "$@"
