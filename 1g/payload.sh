#!/bin/bash

#-# CONFIGURATION #-----------------------------------------------------#
STEALTH_MODE=0			# LEDs (1=on, 0=off)							|
SSH_MODE=1				# SSH server on startup (1=on, 0=off)			|
DNS_MODE=1				# DNS server on startup (1=on, 0=off)			|
DNS_SERVER='8.8.8.8'	# DNS server for VPN (can be changed on website)|
CLEAR_LOGS=0			# Clear log files every boot (not recommended)  |
#-# END CONFIGURATION #-------------------------------------------------#

# Booleans
b_VPN=0
b_DHCP=0
b_DNS=0
b_SSH=0

# PIDs
PID_TCPDUMP=0
PID_PYSERVER=0

# Paths
fs_LOOT="/mnt/PopsWRT"
fs_PAYLOAD=$(dirname $(readlink -f "$0"))
fs_PAYLOADS="$fs_PAYLOAD/custom"
fs_API="$fs_PAYLOADS/api.sh"
fs_FIRSTRUN="/root/PopsWazHere"
fs_LOG="$fs_PAYLOAD/log.txt"
fs_SERVERLOG="$fs_PAYLOAD/serverlog.txt"
fs_OUTPUT="$fs_PAYLOAD/www/output.txt"
fs_POWER="$fs_PAYLOAD/CMD_POWER"
fs_RESET="$fs_PAYLOAD/CMD_RESET"
fs_EXECUTE="$fs_PAYLOAD/CMD_EXECUTE"
fs_EXECUTE_PAYLOAD="$fs_PAYLOAD/CMD_PAYLOAD"
fs_UPDATE="$fs_PAYLOAD/CMD_UPDATE"
fs_CONFIG="$fs_PAYLOAD/cfg"

function log() {
	echo $1 >> $fs_LOG
}

log "+ PopsWRT has started"

# LED overrider - allows me to control whether LEDs should display or not
function sled() {
	if [ "$STEALTH_MODE" = "0" ]; then
		if [ "$1" = "C" ]; then
			LED C 1000
		else
			LED $1
		fi
	else
		log "+ Simulated LED: $1"
	fi
}

# Set DNS for VPN..bad habits taught by the man himself
# Usage: setdns <ip>
# Keep in mind the IP needs to be a string
function setdns() {
	if [ $1 ]; then
		$DNS_SERVER=$1
	fi
	while true; do
		[[ ! $(grep -q "$DNS_SERVER" /tmp/resolv.conf) ]] && {
			echo -e "search lan\nnameserver $DNS_SERVER" > /tmp/resolv.conf
		}
		sleep 5
	done
}

function update() {
	sled W
	source "$fs_CONFIG/config"
	b_NETCHANGE=0
	b_DNSCHANGE=0
	# Network Settings
	#- Netmode
	if [ $fm_netmode ]; then
		log "-+ Updating NETMODE: $fm_netmode"
		NETMODE $fm_netmode
		sleep 3
		b_NETCHANGE=1
		## IP
		if [ $fm_staticip ]; then
			if [ ! "$fm_netmode" = "CLONE" ]; then
				log "-+ Updating Static IP: $fm_staticip"
				uci set network.lan.ipaddr="$fm_staticip"
				b_NETCHANGE=1
			else
				log "-+ Cannot set Static IP - NETMODE is CLONE"
			fi
		fi
	fi
	#- Mask
	if [ $fm_netmask ]; then
		log "-+ Updating Netmask: $fm_netmask"
		uci set network.lan.netmask="$fm_netmask"
		b_NETCHANGE=1
	fi
	#- DHCP
	if [ "$fm_dhcp" = "1" ]; then
		b_DHCP=1
		log "-+ DHCP Enabled"
		if [ $fm_dhcp_start ]; then
			log "--+ Updating start IP for DHCP: $fm_dhcp_start"
			uci set dhcp.lan.start="$fm_dhcp_start"
		else
			log "--+ Using current start IP"
		fi
		if [ $fm_dhcp_limit ]; then
			log "--+ Updating limit for DHCP: $fm_dhcp_limit"
			uci set dhcp.lan.limit="$fm_dhcp_limit"
		else
			log "--+ Using current lease limit"
		fi
		b_DNSCHANGE=1
	else
		b_DHCP=0
		log "-+ DHCP Disabled"
		uci set dhcp.lan.start=100
		uci set dhcp.lan.limit=1
		b_DNSCHANGE=1
	fi
	#- DNS
	if [ "$fm_dns" = "1" ]; then
		b_DNS=1
		log "-+ DNS Enabled"
		#-- Aggressive DNS
		cp "$fs_PAYLOAD/cfg/hosts" "/tmp/dnsmasq.address" &> /dev/null
		if [ "$fm_dns_mode" = "1" ]; then
			log "--+ 'Aggressive Mode' Enabled"
			iptables -A PREROUTING -t nat -i eth0 -p udp --dport 53 -j REDIRECT --to-port 53
		else
			log "--+ 'Aggressive Mode' Disabled"
		fi
		b_DNSCHANGE=1
	else
		b_DNS=0
		log "-+ DNS Disabled"
		uci set dhcp.dnsmasq.port=0
		b_DNSCHANGE=1
	fi
	#- SSH
	if [ "$fm_ssh" = "1" ]; then
		b_SSH=1
		log "-+ SSH Enabled"
	else
		b_SSH=0
	fi
	#- VPN
	if [ "$fm_vpn" = "1" ]; then
		b_VPN=1
		log "-+ VPN Enabled"
		if [ $fm_vpn_dns ]; then
			DNS_SERVER=$fm_vpn_dns
		fi
		#-- Tunnel
		if [ "$fm_vpn_mode" = "1" ]; then
			log "--+ 'Tunnel Mode' Enabled"
			NETMODE BRIDGE
		else
			log "--+ 'Tunnel Mode' Disabled"
			NETMODE VPN
		fi
		uci set openvpn.vpn.config="$fs_CONFIG/config.ovpn"
		b_NETCHANGE=1
	else
		b_VPN=0
		log "-+ VPN Disabled"
	fi
	# Apply changes
	uci commit
	if [ ! "$1" = "1" ]; then
		kill $PID_PYSERVER && log "-+ Killed web server successfully"
		wait $PID_PYSERVER
	fi
	if [ "$b_NETCHANGE" = "1" ]; then
		/etc/init.d/network reload && log "-+ Network reloaded successfully"
	fi
	if [ "$b_DNSCHANGE" = "1" ]; then
		/etc/init.d/dnsmasq restart && log "-+ DNSmasq restarted successfully"
	fi
	if [ "$b_VPN" = "1" ]; then
		/etc/init.d/openvpn start && log "-+ OpenVPN started successfully"
		setdns &
	fi
	if [ "$b_SSH" = "1" ]; then
		/etc/init.d/sshd start &
	fi
	# Make sure everything's come back up before proceeding
	# ~40 seconds is the minimum time - too short and the web server won't come up, too long and you're patience might time out
	sleep 50
	sled Y
}

function run() {
	# Execute a payload
	if [ "$1" = "tcpdump" ]; then
		if [ ! -f /mnt/NO_MOUNT ]; then
			mkdir -p $fs_LOOT/tcpdump
			log "+ Payload 'tcpdump' launching in TIMER mode"
			tcpdump -i br-lan -w "$fs_LOOT/tcpdump/DUMP_$(date +%Y-%m-%d-%H%M%S).pcap" &>/dev/null &
			PID_TCPDUMP=$!
			log "+ Payload 'tcpdump' started with timer of $2 seconds"
			(
				sleep $2
				kill $PID_TCPDUMP
				wait $PID_TCPDUMP
				log "+ Payload 'tcpdump' complete"
				sync
			) &
		else
			log "+ Payload 'tcpdump' error: No external storage"
			sled R
			sleep 1
			sled C
		fi
	# Execute an external payload
	elif [ -d $fs_PAYLOADS/$1 ]; then
		log "+ Payload \'$1\' found, launching"
		source $fs_PAYLOADS/$1/payload.sh
		log "+ Payload \'$1\' completed"
	fi
}

function handler() {
	log "+ Handler has started"
	while [ ! -f $fs_POWER ]; do
		if [ -f $fs_UPDATE ]; then
			# CMD_UPDATE found: start an update
			rm $fs_UPDATE
			log "+ Initializing update"
			update
			log "+ Restarting web server.."
			( python $fs_PAYLOAD/server.py >> $fs_SERVERLOG || log "+ Failed to restart web server, rebooting"; reboot ) &
			PID_PYSERVER=$!
			sled C
			log "+ Update finished"
		elif [ -f $fs_EXECUTE ]; then
			# CMD_EXECUTE found: execute a command
			sled W
			log "+ Command received"
			source $fs_API
			echo "Command: $(cat $fs_EXECUTE)" >> $fs_OUTPUT
			echo "Output:" >> $fs_OUTPUT
			source $fs_EXECUTE >> $fs_OUTPUT
			echo "---" >> $fs_OUTPUT
			sled C
			log "+ Command finished"
			rm -r $fs_EXECUTE
		elif [ -f $fs_EXECUTE_PAYLOAD ]; then
			# CMD_PAYLOAD found: execute a payload
			sled W
			log "+ Payload requested"
			a=$(sed '1q;d' $fs_EXECUTE_PAYLOAD)
			b=$(sed '2q;d' $fs_EXECUTE_PAYLOAD)
			rm -r $fs_EXECUTE_PAYLOAD
			sled C
			if [ "$a" = "tcpdump" ]; then
				run tcpdump $b
			else
				if [ "$b" = "&" ]; then
					run $a &
				else
					run $a
				fi
			fi
		elif [ -f $fs_RESET ]; then
			# CMD_RESET file found: reset configuration
			rm -r $fs_RESET
			sled W
			log "+ Resetting configuration.."
			cp -f "$fs_FIRSTRUN/dhcp.bak" "/etc/config/dhcp"
			log "+ Rebooting.."
			sled G
			reboot
		fi
	done
	# Handler has stopped, let's get ready to go offline for a bit
	log "+ Handler has stopped"
	sled G
	VAR=$(cat $fs_POWER)
	rm -r $fs_POWER
	sled OFF
	if [ "$VAR" = "shutdown" ]; then
		log "+ PopsWRT is shutting down.."
		poweroff
	elif [ "$VAR" = "reboot" ]; then
		log "+ PopsWRT is rebooting.."
		reboot
	fi
}

# The INITIATION function
function init() {
	NETMODE NAT
	sleep 5
	cp "$fs_PAYLOAD/cfg/hosts" "/tmp/dnsmasq.address" &> /dev/null
	if [ "$SSH_MODE" = "1" ]; then
		/etc/init.d/sshd start &
	fi
	if [ "$DNS_MODE" = "1" ]; then
		/etc/init.d/dnsmasq restart
		iptables -A PREROUTING -t nat -i eth0 -p udp --dport 53 -j REDIRECT --to-port 53
	fi
	# Check for existing config, if exists then apply it
	if [ -f "$fs_CONFIG/config" ]; then
		update 1
	fi
	python $fs_PAYLOAD/server.py >> $fs_SERVERLOG &
	PID_PYSERVER=$!
	log "+ Web server has started"
	sled C
	handler
}

# Initiation
if [ -d $fs_FIRSTRUN ]; then
	log "+ PopsWRT has been here before.."
	if [ -f "$fs_FIRSTRUN/network.bak" ] && [ -f "$fs_FIRSTRUN/dhcp.bak" ]; then
		# Don't need to obtain backups of config
		log "+ Backup files found, continuing boot"
	else
		# No backups! Grab 'em, quick!
		log "+ No backup files found, creating now"
		cp "/etc/config/network" "$fs_FIRSTRUN/network.bak"
		cp "/etc/config/dhcp" "$fs_FIRSTRUN/dhcp.bak"
	fi
else
	# Obtain backups of config
	log "+ Setting up first time use for PopsWRT.."
	mkdir -p $fs_FIRSTRUN
	cp "/etc/config/network" "$fs_FIRSTRUN/network.bak"
	cp "/etc/config/dhcp" "$fs_FIRSTRUN/dhcp.bak"
fi
# Check if we need to clear previous logs
if [ "$CLEAR_LOGS" = "1" ]; then
	if [ -f $fs_LOG ]; then
		rm $fs_LOG
	fi
	if [ -f $fs_SERVERLOG ]; then
		rm $fs_SERVERLOG
	fi
fi

init