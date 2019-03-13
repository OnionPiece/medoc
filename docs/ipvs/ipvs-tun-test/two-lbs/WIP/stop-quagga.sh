#!/bin/bash
#
# run as root

pkill -9 -f "zebra -f /opt/edge-router-zebra.conf"
pkill -9 -f "ospfd -f /opt/edge-router-ospfd.conf"
rm -rf /opt/edge-router-*
