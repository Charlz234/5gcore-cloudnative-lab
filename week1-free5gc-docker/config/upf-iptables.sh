#!/bin/bash
#
# Configure iptables in UPF
#
iptables -t nat -A POSTROUTING -o ens4 -j MASQUERADE
iptables -I FORWARD 1 -j ACCEPT

