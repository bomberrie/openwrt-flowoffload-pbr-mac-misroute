# OpenWrt Flow Offload + PBR + NAT Reproducer

This repository provides a reproducer, diagnostic tooling, and a mitigation for an OpenWrt 24.10.0 routing bug.

## The Bug

When software or hardware flow offloading is enabled in OpenWrt 24.10.0, policy-routed NAT traffic is misdelivered to the wrong LAN MAC address. The destination MAC resolves to the PBR next-hop or VPN gateway instead of the targeted local host.

## Reproduction Lab

The lab uses Linux network namespaces to simulate the routing topology. The host requires a kernel with `nftables` and `flowtable` support, along with `iproute2`, `nft`, `conntrack-tools`, `tcpdump`, and `python3`. Execute all commands as root.

Start the environment:

```bash
./reproducer/netns-lab.sh run
```

This creates the namespaces, loads nftables rules, generates A and AAAA DNS queries, captures MAC addresses on the wire, and dumps the flowtable.

Lab environment variables:
* `FLOW_OFFLOAD=1`: Enables nft flowtable offloading (default is 0).
* `MITIGATION=0`: Disables the mitigation rules to expose the bug.
* `USE_PBR_MARK=0`: Bypasses tagging DNS flows with `fwmark 0xff` in table 100 (default is 1).
* `DNS_QUERIES=<n>`: Sets concurrent UDP queries to stress the flowtable (default is 4).
* `CLEAN_LOGS=1`: Purges `reproducer/output/*.{pcap,log}` on teardown.

Convenience targets:
* `make smoke`: Runs the lab testing offload states with the mitigation applied.
* `make clean`: Tears down namespaces and purges logs.
* `make diag`: Executes `diagnostics/collect.sh` locally.

## Mitigation

The mitigation injects a `firewall4` include that bypasses flow offloading for traffic marked by PBR (`meta mark != 0`) or processed by NAT (`ct status { dnat, snat }`). The performance penalty is isolated to these affected flows.

### OpenWrt Installation

Apply the hotfix directly via SSH:
```bash
ssh root@router 'sh -s' < mitigation/apply.sh
```

Revert the hotfix:
```bash
ssh root@router 'sh -s' < mitigation/rollback.sh
```

To build and install via `ipk` package:
1. Build on a Linux host: `./scripts/build-ipk.sh` (uses latest git tag; override with `VERSION=0.1.0`).
2. Transfer and install: `scp dist/openwrt-flowoffload-pbr-mitigation_<ver>_all.ipk root@router:/tmp && ssh root@router opkg install /tmp/openwrt-flowoffload-pbr-mitigation_<ver>_all.ipk`.

Installation automatically reloads `firewall4` to apply the include. Removing the package drops the rules.

For manual persistence, copy `mitigation/firewall4-offload-mitigation.nft` to `/etc/nftables.d/99-flowoffload-pbr.nft` and run `/etc/init.d/firewall restart`.

## Diagnostics and Triage

To debug on OpenWrt hardware, install the required packages: `opkg update && opkg install tcpdump conntrack-tools`. Transfer `diagnostics/collect.sh` to the router to gather state.

Manual triage commands:
* Trace packet path: `sudo nft monitor trace`
* Inspect flowtable state: `sudo nft list flowtable inet filter ftoffload`
* Monitor ARP/ND churn: `sudo ip -s neigh show`
* Capture LAN L2 headers: `sudo tcpdump -nn -e -i br-lan udp port 53`
* Watch conntrack events: `sudo conntrack -E -p udp`

## Upstream Status

When filing reports against OpenWrt `firewall4`, `netfilter`, or the kernel, attach the outputs from `nft list ruleset`, `ip route show table all`, `conntrack -L`, and the `tcpdump` traces. 

A proposed `firewall4` patch is located at `patches/firewall4-flowoffload-pbr.patch`. Further kernel investigation is needed regarding flowtable neighbor and route caching interactions with `skb` marks and NAT, specifically on the `mt7621` hardware offload path.

## Repository Layout

* README.md — Overview, quick start, and upstreaming notes.
* `docs/theory-of-failure.md` — Packet path analysis and measurements.
* `reproducer/` — The netns lab and traffic generator.
* `diagnostics/` — Data collection scripts.
* `mitigation/` — `firewall4` include, installer, and rollback scripts.
* `patches/` — Proposed `firewall4` patch and upstreaming guidance.
* `scripts/smoke-test.sh` — CI-friendly check of the lab and mitigation.
