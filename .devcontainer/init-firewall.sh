#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

echo "Setting up basic firewall..."

# Save Docker DNS rules before flushing
DOCKER_DNS_RULES=$(iptables-save -t nat 2>/dev/null | grep "127.0.0.11" || true)

iptables -F
iptables -X
iptables -t nat -F 2>/dev/null || true
iptables -t nat -X 2>/dev/null || true
iptables -t mangle -F 2>/dev/null || true
iptables -t mangle -X 2>/dev/null || true

# Restore Docker DNS rules
if [ -n "$DOCKER_DNS_RULES" ]; then
    echo "Restoring Docker DNS rules..."
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat 2>/dev/null || true
fi

# Allow DNS
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
iptables -A INPUT -p udp --sport 53 -j ACCEPT
iptables -A INPUT -p tcp --sport 53 -j ACCEPT

# Allow localhost
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Allow SSH
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT

# Allow standard outbound: HTTP, HTTPS (Claude API, GitHub, npm, etc.)
iptables -A OUTPUT -p tcp --dport 80 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT

# Allow host network
HOST_IP=$(ip route | grep default | cut -d" " -f3 2>/dev/null || echo "")
if [ -n "$HOST_IP" ]; then
    HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
    echo "Host network detected as: $HOST_NETWORK"
    iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
    iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT
fi

# Default DROP
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Reject other outbound
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

echo "Basic firewall active (HTTP/HTTPS/DNS/SSH allowed)"

# Quick connectivity check
if curl --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
    echo "OK: GitHub reachable"
else
    echo "WARNING: GitHub unreachable"
fi

if curl --connect-timeout 5 https://api.anthropic.com >/dev/null 2>&1; then
    echo "OK: Anthropic API reachable"
else
    echo "WARNING: Anthropic API unreachable"
fi
