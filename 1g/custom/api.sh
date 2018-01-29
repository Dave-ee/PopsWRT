#!/bin/bash

# This is the API file. 
# It allows you to call functions from the CLI in PopsWRT for quick information.

# List of available commands:
# run <payload>
# - Run a custom payload or even 'tcpdump'
# tellme <arg>
# - List of arguments:
# -- netmode
# -- ip
# -- netmask
# -- dhcp start
# -- dhcp limit
# -- config
# sled <colour>
# - Sets the LED colour (doesn't turn on LED if stealth mode is on)
# log <arg>
# - Writes the argument straight to the main log file

# Used to display output in the textarea
# Does nothing different to "echo" at the moment, but it could do more..
function output() {
	echo $1
}

# Tells you general information
function tellme() {
	$var="nil"
	if [ "$1" = "?" ]; then
		output "Arguments:"
		output "netmode -> returns netmode"
		output "ip -> returns current ip"
		output "netmask -> returns netmask"
		output "dhcp start -> returns dhcp start"
		output "dhcp limit -> returns dhcp limit"
		output "config -> returns contents of config file"
	elif [ "$1" = "netmode" ]; then
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
	elif [ "$1" = "config" ]; then
		if [ -f $fs_CONFIG/config ]; then
			var=$(cat $fs_CONFIG/config)
		else
			var="default - no configuration has been pushed yet"
		fi
	fi
	if [ ! "$var" = "nil" ]; then
		output $var
	fi
}