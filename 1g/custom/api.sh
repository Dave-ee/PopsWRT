#!/bin/bash

# This is the API file. 
# It allows you to call functions from the CLI in PopsWRT for quick information.

# List of available commands:
# run <payload>
# - Run a custom payload or even 'tcpdump'
# tellme <arg>
# Arguments:
# -- netmode			# Returns the netmode
# -- ip					# Returns the ip
# -- netmask			# Returns the netmask
# -- dhcp start			# Returns the starting host ID
# -- dhcp limit			# Returns the IP-leasing limit set for the DHCP server
# -- config				# Returns output of config file
# -- dns 				# Returns the current DNS server set for the VPN
# -- service <service> 	# Returns if a service is running or not. Services: SSH, DNS, DHCP, VPN
# sled <colour>
# -- Set the colour of the LED (if STEALTH_MODE is on then it won't do anything)
# log <text>
# -- Output the argument to the log file

# Used to display output in the textarea
# Does nothing different to "echo" at the moment, but it could do more..
function output() {
	echo $1
}

# Tells you general information
function tellme() {
	$var=""
	if [ "$1" = "netmode" ]; then
		if [ $fm_netmode ]; then
			var=$fm_netmode
		else
			var="nat"
		fi
	elif [ "$1" = "ip" ]; then
		var=$(uci get network.lan.ipaddr)
	elif [ "$1" = "netmask" ]; then
		var=$(uci get network.lan.netmask)
	elif [ "$1" = "dhcp" ]; then
		if [ "$2" = "start" ]; then
			var=$(uci get dhcp.lan.start)
		elif [ "$2" = "limit" ]; then
			var=$(uci get dhcp.lan.limit)
		fi
	elif [ "$1" = "dns" ]; then
		var="$DNS_SERVER"
	elif [ "$1" = "config" ]; then
		if [ -f $fs_CONFIG/config ]; then
			var=$(cat $fs_CONFIG/config)
		else
			var="default - no configuration has been pushed yet"
		fi
	elif [ "$1" = "service" ]; then
		if [ "$2" = "dns" ]; then
			var=$b_DNS
		elif [ "$2" = "ssh" ]; then
			var=$b_SSH
		elif [ "$2" = "dhcp" ]; then
			var=$b_DHCP
		elif [ "$2" = "vpn" ]; then
			var=$b_VPN
		fi
	fi
	output $var
}