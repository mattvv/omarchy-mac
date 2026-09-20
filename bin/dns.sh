#!/usr/bin/env bash
# DNS presets, applied to whichever network service is actually carrying
# traffic. Upstream hardcodes nothing because Linux has one resolver; here the
# machine may be on Wi-Fi, a dock's ethernet, or a phone, and setting DNS on the
# wrong service silently does nothing at all.
set -uo pipefail

active_service() {
  local dev
  dev=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
  [ -n "$dev" ] || return 1
  # `listnetworkserviceorder` pairs a human name with its device one line later.
  networksetup -listnetworkserviceorder 2>/dev/null | awk -v dev="$dev" '
    /^\([0-9]+\)/ { name = substr($0, index($0, ") ") + 2) }
    /Device:/     { if ($0 ~ "Device: " dev "\\)") { print name; exit } }'
}

case "${1:-status}" in
  status)
    svc=$(active_service) || { echo "no active service"; exit 1; }
    servers=$(networksetup -getdnsservers "$svc" 2>/dev/null)
    case "$servers" in
      *"aren't any"*) echo "$svc: DHCP" ;;
      *) echo "$svc: $(echo "$servers" | tr '\n' ' ')" ;;
    esac ;;
  dhcp|cloudflare|google|quad9)
    svc=$(active_service) || { echo "no active service" >&2; exit 1; }
    case "$1" in
      dhcp)       networksetup -setdnsservers "$svc" "Empty" ;;
      cloudflare) networksetup -setdnsservers "$svc" 1.1.1.1 1.0.0.1 ;;
      google)     networksetup -setdnsservers "$svc" 8.8.8.8 8.8.4.4 ;;
      quad9)      networksetup -setdnsservers "$svc" 9.9.9.9 149.112.112.112 ;;
    esac
    echo "$svc -> $1" ;;
  *)
    echo "usage: dns.sh [status|dhcp|cloudflare|google|quad9]" >&2; exit 2 ;;
esac
