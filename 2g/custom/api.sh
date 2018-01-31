#!/bin/bash

# This is the API file. 
# It allows you to call functions from the CLI in PopsWRT for quick information.

# List of available commands:
# run <payload>
# - Run a custom payload or even 'tcpdump'
# tellme <arguments..>
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
# cfg <import|export> <path>
# -- Importing requires an existing config file path
# -- Exporting requires a path to export current config file to
# svc <service> <arguments..>
# Arguments:
# -- dns
# 	-- restart
#	-- stop
#	-- aggressive <enable|disable>
# -- dhcp
# 	-- restart
#	-- stop
# -- ssh
#	-- restart
#	-- stop
# -- vpn
#	-- config <path>
#	-- tunnel <enable|disable>
#	-- dns <ip>
#	-- stop
#	-- start

# Used to display output in the textarea
# Does nothing different to "echo" at the moment, but it could do more..
function output {
	echo $1
	log "+ COMMAND OUTPUT: $1"
}

# Tells you general information
function tellme {
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
		var="$cf_DNS"
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

# Configuration Management
function cfg {
	if [ "$1" = "import" ]; then
		if [ -f "$2" ]; then
			output "Configuration file found, updating"
			update "$2"
		else
			output "Path doesn't exist"
		fi
	elif [ "$1" = "export" ]; then
		if [ "$2" ]; then
			if [ -f "$fs_CONFIG" ]; then
				cp "$fs_CONFIG" "$2"
				output "Configuration file exported to $2"
			else
				output "Cannot export default configuration"
			fi
		else
			output "No path given."
		fi
	fi
}

# Service Management
function svc {
	if [ "$1" = "dns" ]; then
		if [ "$2" = "restart" ]; then
			bl_DNS=1
			output "SVC: Restarting DNSMasq service"
			/etc/init.d/dnsmasq restart
		elif [ "$2" = "stop" ]; then
			output "SVC: Stopping DNS service, temporarily restarting DNSMasq"
			bl_DNS=0
			uci set dhcp.dnsmasq.port=0
			uci commit
			/etc/init.d/dnsmasq restart
		elif [ "$2" = "aggressive" ]; then
			if [ "$3" = "enable" ]; then
				output "SVC: Aggressive mode enabled"
				iptables -A PREROUTING -t nat -i eth0 -p udp --dport 53 -j REDIRECT --to-port 53
			elif [ "$3" = "disable" ]; then
				output "SVC: Aggressive mode disabled"
				iptables -D PREROUTING -t nat -i eth0 -p udp --dport 53 -j REDIRECT --to-port 53
			else
				output "SVC: Aggressive accepts 'enable' or 'disable'"
			fi
		else
			output "SVC: Unknown argument"
		fi
	elif [ "$1" = "dhcp" ]; then
		if [ "$2" = "restart" ]; then
			bl_DHCP=1
			output "SVC: Restarting DNSMasq service"
			/etc/init.d/dnsmasq restart
		elif [ "$2" = "stop" ]; then
			output "SVC: Stopping DHCP service, temporarily restarting DNSMasq"
			bl_DHCP=0
			uci set dhcp.lan.start=100
			uci set dhcp.lan.limit=1
			uci commit
			/etc/init.d/dnsmasq restart
		else
			output "SVC: Unknown argument"
		fi
	elif [ "$1" = "ssh" ]; then
		if [ "$2" = "start" ]; then
			bl_SSH=1
			/etc/init.d/sshd start &
			id_SSH=$!
		elif [ "$2" = "stop" ]; then
			bl_SSH=0
			/etc/init.d/sshd stop
			# Just to be sure..
			if [ ! "$id_SSH" = "0" ]; then
				kill "$id_SSH"
				wait "$id_SSH"
				id_SSH=0
			fi
		fi
	elif [ "$1" = "vpn" ]; then
		if [ "$2" = "config" ]; then
			if [ -f "$3" ]; then
				uci set openvpn.vpn.config="$3"
				uci commit
			fi
		elif [ "$2" = "tunnel" ]; then
			if [ "$3" = "enable" ]; then
				output "SVC: Tunnel mode enabled, restarting VPN service.."
				NETMODE BRIDGE
				sleep 5
				/etc/init.d/openvpn start
			elif [ "$3" = "disable" ]; then
				output "SVC: Tunnel mode disabled, restarting VPN service.."
				NETMODE VPN
				sleep 5
				/etc/init.d/openvpn start
			else
				output "SVC: Tunnel accepts 'enable' or 'disable'"
			fi
		elif [ "$2" = "dns" ]; then
			if [ "$3" ]; then
				setdns "$3"
			fi
		elif [ "$2" = "stop" ]; then
			output "SVC: Stopped VPN service"
			/etc/init.d/openvpn stop
			if [ ! "$id_SETDNS" = "0" ]; then
				kill "$id_SETDNS"
				wait "$id_SETDNS"
				id_SETDNS=0
			fi
		elif [ "$2" = "start" ]; then
			/etc/init.d/openvpn start
			setdns
		else
			output "SVC: Unknown argument"
		fi
	else
		output "SVC: Unknown argument"
	fi
}