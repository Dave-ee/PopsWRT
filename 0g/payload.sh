#!/bin/bash

### CONFIGURATION #######################################################
STEALTH_MODE=0			# LEDs (1=on, 0=off)							#
SSH_MODE=1				# SSH server on startup (1=on, 0=off)			#
DNS_MODE=1				# DNS server on startup (1=on, 0=off)			#
DNS_SERVER='8.8.8.8'	# DNS server for VPN (can be changed on website)#
ON_FINISH="halt"		# What to do on finish (halt, reboot, poweroff)	#
### END CONFIGURATION ###################################################

# Booleans
b_VPN=0
b_DHCP=0
b_SSH=0
b_DNS=0

# PIDs
PID_TCPDUMP=0
PID_PYSERVER=0

# Paths
fs_LOOT="/mnt/PopsWRT"
fs_PAYLOAD=$(dirname $(readlink -f "$0"))
fs_PAYLOADS="$fs_PAYLOAD/custom"
fs_FIRSTRUN="/root/PopsWazHere"
fs_LOG="$fs_PAYLOAD/log.txt"
fs_SERVERLOG="$fs_PAYLOAD/serverlog.txt"
fs_OUTPUT="$fs_PAYLOAD/www/output.txt"
fs_SHUTDOWN="$fs_PAYLOAD/CMD_SHUTDOWN"
fs_EXECUTE="$fs_PAYLOAD/CMD_EXECUTE"
fs_EXECUTE_PAYLOAD="$fs_PAYLOAD/CMD_PAYLOAD"
fs_UPDATE="$fs_PAYLOAD/CMD_UPDATE"
fs_CONFIG="$fs_PAYLOAD/cfg/config.ini"

function log() {
	echo $1 >> $fs_LOG
}

log "+ PopsWRT has started"

function sled() {
	if [ "$STEALTH_MODE" = "0" ]; then
		if [ "$1" = "W" ]; then
			LED W
		elif [ "$1" = "R" ]; then
			LED R
		elif [ "$1" = "G" ]; then
			LED FINISH
		else
			LED $1 1000
		fi
	else
		log "+ Simulated LED: $1"
	fi
}

function setdns() {
	while true; do
		[[ ! $(grep -q "$DNS_SERVER" /tmp/resolv.conf) ]] && {
			echo -e "search lan\nnameserver $DNS_SERVER" > /tmp/resolv.conf
		}
		sleep 5
	done
}

function update() {
	source $fs_CONFIG
	b_NETCHANGE=0
	b_DNSCHANGE=0
	# Network Settings
	## Netmode
	if [ $fm_netmode ]; then
		log "-+ Updating NETMODE: $fm_netmode"
		NETMODE $fm_netmode
		sleep 3
		b_NETCHANGE=1
	fi
	## IP
	if [ $fm_staticip ]; then
		log "-+ Updating Static IP: $fm_staticip"
		uci set network.lan.ipaddr="$fm_staticip"
		b_NETCHANGE=1
	fi
	## Mask
	if [ $fm_netmask ]; then
		log "-+ Updating Netmask: $fm_netmask"
		uci set network.lan.netmask="$fm_netmask"
		b_NETCHANGE=1
	fi
	## DHCP
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
	## DNS
	if [ "$fm_dns" = "1" ]; then
		b_DNS=1
		log "-+ DNS Enabled"
		### Aggressive DNS
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
	## SSH
	if [ "$fm_ssh" = "1" ]; then
		b_SSH=1
		log "-+ SSH Enabled"
	else
		b_SSH=0
	fi
	## VPN
	if [ "$fm_vpn" = "1" ]; then
		b_VPN=1
		log "-+ VPN Enabled"
		if [ $fm_vpn_dns ]; then
			DNS_SERVER=$fm_vpn_dns
		fi
		### Tunnel
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
	kill $PID_PYSERVER && log "-+ Killed web server successfully"
	wait $PID_PYSERVER
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
	# Make sure every thing's come back up before proceeding
	sleep 60
}

function run() {
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
	elif [ -d $fs_PAYLOADS/$1 ]; then
		log "+ Payload \'$1\' found, launching"
		source $fs_PAYLOADS/$1/payload.sh
		log "+ Payload \'$1\' completed"
	fi
}

function handler() {
	log "+ Handler has started"
	while [ ! -f $fs_SHUTDOWN ]; do
		if [ -f $fs_UPDATE ]; then
			sled W
			log "+ Initializing Update"
			update
			sled Y
			( python $fs_PAYLOAD/server.py >> $fs_SERVERLOG || log "-+ Failed to start web server"; reboot ) &
			PID_PYSERVER=$!
			sled C
			log "+ Update finished"
			rm -r $fs_UPDATE
		elif [ -f $fs_EXECUTE ]; then
			sled W
			log "+ Command received"
			source $fs_EXECUTE > $fs_OUTPUT
			sled C
			log "+ Command finished"
			rm -r $fs_EXECUTE
		elif [ -f $fs_EXECUTE_PAYLOAD ]; then
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
		fi
	done
	log "+ Handler has stopped"
}

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
	python $fs_PAYLOAD/server.py >> $fs_SERVERLOG &
	PID_PYSERVER=$!
	log "+ Web server has started"
	sled C
	handler
}

function finish() {
	rm -r $fs_SHUTDOWN
	sled G
	sync
	log "+ PopsWRT has finished"
	sled OFF
	case "$ON_FINISH" in
		"poweroff") poweroff ;;
		"reboot") reboot ;;
		"halt") halt ;;
		*) reboot;;
	esac
}

if [ -f $fs_FIRSTRUN ]; then
	log "+ PopsWRT has been here before.."
else
	# Obtain backups of config
	log "+ Setting up first time use for PopsWRT.."
	mkdir -p $fs_FIRSTRUN
	cp "/etc/config/network" "$fs_FIRSTRUN/network.bak"
	cp "/etc/config/dhcp" "$fs_FIRSTRUN/dhcp.bak"
fi
if [ -f $fs_LOG ]; then
	rm -r $fs_LOG
fi
if [ -f $fs_SERVERLOG ]; then
	rm -r $fs_SERVERLOG
fi

init
finish