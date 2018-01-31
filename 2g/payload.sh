#!/bin/bash

md_STEALTH=0				# Enable LED
md_SSH_ON_START=1			# Startup with SSH
md_DNS_ON_START=1			# Startup with DNS
cf_DNS="8.8.8.8"			# Set DNS server for VPN
cf_CLEAR_LOG_ON_START=0		# Startup with fresh log files

# Boolean Watch
bl_VPN=0
bl_DHCP=0
bl_DNS=0
bl_SSH=0

# PID
id_TCPDUMP=0
id_PYSERVER=0
id_SETDNS=0
id_SSH=0

# Paths - Directory
fs_DIR_LOOT="/mnt/PopsWRT"
fs_DIR_SWITCH=$(dirname "$(readlink -f "$0")")
fs_DIR_CUSTOM="$fs_DIR_SWITCH/custom"
fs_DIR_FIRSTRUN="/root/PopsWazHere"
fs_DIR_WWW="$fs_DIR_SWITCH/www"
fs_DIR_CFG="$fs_DIR_SWITCH/cfg"

# Paths - Files
fs_API="$fs_DIR_CUSTOM/api.sh"
fs_LOG="$fs_DIR_SWITCH/log.txt"
fs_LOG_SERVER="$fs_DIR_SWITCH/serverlog.txt"
fs_CONFIG=""
fs_OUTPUT="$fs_DIR_WWW/output.txt"
fs_CMD_POWER="$fs_DIR_SWITCH/CMD_POWER"
fs_CMD_RESET="$fs_DIR_SWITCH/CMD_RESET"
fs_CMD_EXECUTE="$fs_DIR_SWITCH/CMD_EXECUTE"
fs_CMD_PAYLOAD="$fs_DIR_SWITCH/CMD_PAYLOAD"
fs_CMD_UPDATE="$fs_DIR_SWITCH/CMD_UPDATE"

# Echo argument to log file
function log {
	echo "$1" >> "$fs_LOG"
}

log "+ PopsWRT has started"

# Set LED colour if not in Stealth mode
function sled {
	if [ "$md_STEALTH" = "0" ]; then
		if [ "$1" = "C" ]; then
			LED C 1000
		else
			LED "$1"
		fi
	else
		log "+ Simulated LED: $1"
	fi
}

# Set VPN DNS
# Can be used by CLI. Usage: setdns <ip-as-string>
function setdns {
	if [ "$1" ]; then
		cf_DNS="$1"
		echo "Set DNS to $1" >> "$fs_OUTPUT"
	fi
	if [ ! "$id_SETDNS" = "0" ]; then
		kill "$id_SETDNS"
		wait "$id_SETDNS"
		id_SETDNS=0
	fi
	( while true; do
		[[ ! $(grep -q "$cf_DNS" /tmp/resolv.conf) ]] && {
			echo -e "search lan\nnameserver $cf_DNS" > /tmp/resolv.conf
		}
		sleep 5
	done ) &
	id_SETDNS=$!
}

# Update via a config file
function update {
	sled W
	if [ ! -f "$1" ]; then
		echo "+ ERROR: Update file doesn't exist"
		return
	fi
	fs_CONFIG="$1"
	source "$1"
	bl_CHANGE_NET=0
	# NETMODE
	if [ "$fm_netmode" ]; then
		log "-+ NETMODE: $fm_netmode"
		NETMODE "$fm_netmode"
		sleep 3
		bl_CHANGE_NET=1
		# IP
		if [ "$fm_staticip" ]; then
			if [ ! "$fm_netmode" = "CLONE" ]; then
				log "-+ STATIC IP: $fm_staticip"
				uci set network.lan.ipaddr="$fm_staticip"
			else
				log "-+ WARNING: Static IP wasn't set because NETMODE is CLONE"
			fi
		fi
	fi
	# MASK
	if [ "$fm_netmask" ]; then
		log "-+ NETMASK: $fm_netmask"
		uci set network.lan.netmask="$fm_netmask"
		bl_CHANGE_NET=1
	fi
	# DHCP
	if [ "$fm_dhcp" = "1" ]; then
		bl_DHCP=1
		log "-+ DHCP Enabled"
		if [ "$fm_dhcp_start" ]; then
			log "--+ HOST ID: $fm_dhcp_start"
			uci set dhcp.lan.start="$fm_dhcp_start"
		fi
		if [ "$fm_dhcp_limit" ]; then
			log "--+ LEASE LIMIT: $fm_dhcp_limit"
			uci set dhcp.lan.limit="$fm_dhcp_limit"
		fi
	else
		bl_DHCP=0
		log "-+ DHCP Disabled"
		uci set dhcp.lan.start=100
		uci set dhcp.lan.limit=1
	fi
	# DNS
	if [ "$fm_dns" = "1" ]; then
		bl_DNS=1
		log "-+ DNS Enabled"
		cp "$fs_DIR_CFG/hosts" "/tmp/dnsmasq.address" &> /dev/null
		if [ "$fm_dns_mode" = "1" ]; then
			log "--+ AGGRESSIVE MODE Enabled"
			iptables -A PREROUTING -t nat -i eth0 -p udp --dport 53 -j REDIRECT --to-port 53
		else
			log "--+ AGGRESSIVE MODE Disabled"
		fi
	else
		bl_DNS=0
		log "-+ DNS Disabled"
		uci set dhcp.dnsmasq.port=0
	fi
	# SSH
	if [ "$fm_ssh" = "1" ]; then
		bl_SSH=1
		log "-+ SSH Enabled"
	else
		b_SSH=0
	fi
	# VPN
	if [ "$fm_vpn" = "1" ]; then
		bl_VPN=1
		log "-+ VPN Enabled"
		if [ "$fm_vpn_dns" ]; then
			cf_DNS="$fm_vpn_dns"
		fi
		if [ "$fm_vpn_mode" = "1" ]; then
			log "--+ TUNNEL MODE Enabled"
			log "--+ NETMODE: BRIDGE"
			NETMODE BRIDGE
		else
			log "--+ TUNNEL MODE Disabled"
			log "--+ NETMODE: VPN"
			NETMODE VPN
		fi
		uci set openvpn.vpn.config="$fs_DIR_CFG/config.ovpn"
		bl_CHANGE_NET=1
	else
		bl_VPN=0
		log "-+ VPN Disabled"
	fi
	# Apply
	uci commit
	if [ ! "$1" = "1" ]; then
		kill "$id_PYSERVER" && log "-+ Killed web server successfully"
		wait "$id_PYSERVER"
	fi
	if [ "$bl_CHANGE_NET" = "1" ]; then
		/etc/init.d/network reload && log "-+ Network reloaded successfully"
	fi
	if [ "$bl_VPN" = "1" ]; then
		/etc/init.d/openvpn start && log "-+ OpenVPN started successfully"
		setdns
	fi
	if [ "$bl_SSH" = "1" ]; then
		/etc/init.d/sshd start &
		id_SSH=$!
	fi
	/etc/init.d/dnsmasq restart && log "-+ DNSmasq restarted successfully"
	# Wait for the network..
	# ~40s minimum - too short and the web server won't come up, but too long and your patience may time out
	sleep 50
	sleep Y
}

# Run module/payload
function run {
	if [ "$1" = "tcpdump" ]; then
		if [ ! -f /mnt/NO_MOUNT ]; then
			mkdir -p "$fs_DIR_LOOT/tcpdump"
			log "+ Payload Launched: TCPDUMP"
			log "+ Payload Mode: TIMER"
			tcpdump -i br-lan -w "$fs_DIR_LOOT/tcpdump/DUMP_$(date +%Y-%m-%d-%H%M%S).pcap" &>/dev/null &
			id_TCPDUMP=$!
			log "+ TIMER: $2 seconds"
			( sleep $2
			kill "$id_TCPDUMP"
			wait "$id_TCPDUMP"
			log "+ Payload Complete: TCPDUMP"
			sync
			) &
		else
			log "+ ERROR: TCPDump - No external storage"
			sled R
			sleep 1
			sled C
		fi
	elif [ -d "$fs_DIR_CUSTOM/$1" ]; then
		if [ -f "$fs_DIR_CUSTOM/$1/payload.sh" ]; then
			log "+ Payload Launched: $1"
			source "$fs_DIR_CUSTOM/$1/payload.sh"
			log "+ Payload Completed: $1"
		else
			log "+ ERROR: $1 - No 'payload.sh' found"
			sled R
			sleep 1
			sled C
		fi
	else
		log "+ ERROR: Payload doesn't exist"
	fi
}

# Handler function
function handler {
	log "+ Handler has started"
	while [ ! -f "$fs_CMD_POWER" ]; do
		if [ -f "$fs_CMD_UPDATE" ]; then
			# CMD_UPDATE
			log "+ HANDLER: Initializing update"
			update "$(cat "$fs_CMD_UPDATE")"
			log "+ HANDLER: Restarting web server.."
			( python "$fs_DIR_SWITCH/server.py" >> "$fs_LOG_SERVER" || log "+ ERROR: Failed to restart web server, rebooting"; reboot ) &
			id_PYSERVER=$!
			sled C
			log "+ HANDLER: Update finished"
			rm "$fs_CMD_UPDATE"
		elif [ -f "$fs_CMD_EXECUTE" ]; then
			# CMD_EXECUTE
			sled W
			log "+ HANDLER: Command received"
			source "$fs_API"
			echo "Command: " >> "$fs_OUTPUT"
			echo "$(cat "$fs_CMD_EXECUTE")" >> "$fs_OUTPUT"
			echo "Output:" >> "$fs_OUTPUT"
			source "$fs_CMD_EXECUTE" >> "$fs_OUTPUT"
			echo "---" >> "$fs_OUTPUT"
			sled C
			log "+ HANDLER: Command complete"
			rm "$fs_CMD_EXECUTE"
		elif [ -f "$fs_CMD_PAYLOAD" ]; then
			# CMD_PAYLOAD
			sled W
			log "+ HANDLER: Payload requested"
			a=$(sed '1q;d' $fs_CMD_PAYLOAD)
			b=$(sed '2q;d' $fs_CMD_PAYLOAD)
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
			rm "$fs_CMD_PAYLOAD"
		elif [ -f "$fs_CMD_RESET" ]; then
			# CMD_RESET
			sled W
			log "+ HANDLER: Resetting configuration.."
			cp -f "$fs_DIR_FIRSTRUN/dhcp.bak" "/etc/config/dhcp"
			log "+ HANDLER: Rebooting PopsWRT.."
			sled G
			reboot
		fi
	done
	log "+ Handler has stopped"
	sled G
	VAR="$(cat "$fs_CMD_POWER")"
	rm "$fs_CMD_POWER"
	sled OFF
	if [ "$VAR" = "shutdown" ]; then
		log "+ PopsWRT is shutting down.."
		poweroff
	elif [ "$VAR" = "reboot" ]; then
		log "+ PopsWRT is rebooting.."
		reboot
	fi
}

# Init
function init {
	NETMODE NAT
	sleep 5
	if [ "$md_SSH_ON_START" = "1" ]; then
		log "+ INIT: Starting SSH.."
		bl_SSH=1
		/etc/init.d/sshd start &
		id_SSH=$!
	fi
	if [ "$md_DNS_ON_START" = "1" ]; then
		log "+ INIT: Starting DNS/DHCP.."
		bl_DNS=1
		cp "$fs_DIR_CFG/hosts" "/tmp/dnsmasq.address" &> /dev/null
		/etc/init.d/dnsmasq restart
		iptables -A PREROUTING -t nat -i eth0 -p udp --dport 53 -j REDIRECT --to-port 53
	fi
	if [ -f "$fs_DIR_CFG/config" ]; then
		log "+ INIT: Applying update.."
		update "$fs_DIR_CFG/config"
	fi
	python "$fs_DIR_SWITCH/server.py" >> "$fs_LOG_SERVER" &
	id_PYSERVER=$!
	log "+ INIT: Webserver has started"
	sled C
	handler
}

# Boot
if [ -d "$fs_DIR_FIRSTRUN" ]; then
	log "+ BOOT: PopsWRT has been here before.."
	if [ -f "$fs_DIR_FIRSTRUN/network.bak" ] && [ -f "$fs_DIR_FIRSTRUN/dhcp.bak" ]; then
		log "+ BOOT: Backup files found"
	else
		log "+ BOOT: No backup files found"
		cp "/etc/config/network" "$fs_DIR_FIRSTRUN/network.bak"
		cp "/etc/config/dhcp" "$fs_DIR_FIRSTRUN/dhcp.bak"
		log "+ BOOT: Backup files have been created"
	fi
else
	log "+ BOOT: Setting up first time use for PopsWRT.."
	mkdir -p "$fs_DIR_FIRSTRUN"
	cp "/etc/config/network" "$fs_DIR_FIRSTRUN/network.bak"
	cp "/etc/config/dhcp" "$fs_DIR_FIRSTRUN/dhcp.bak"
fi
if [ "$cf_CLEAR_LOG_ON_START" = "1" ]; then
	if [ -f "$fs_LOG" ]; then
		rm "$fs_LOG"
	fi
	if [ -f "$fs_LOG_SERVER" ]; then
		rm "$fs_LOG_SERVER"
	fi
	log "+ BOOT: Logs have been cleared"
fi

init