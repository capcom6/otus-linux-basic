#!/bin/bash

if [[ ! -a /etc/selinux/config ]]; then
	echo "SELinux config is not found. Ensure that SELinux installed."
	exit 1
fi

if [ `id -u` -ne 0 ]; then
	IS_ROOT=false
	echo "Read-only mode. To change settings run as root. For example: sudo $0"
else
	IS_ROOT=true
fi

echo ""
selinuxenabled
if [[ $? -eq 0 ]]; then
	echo 'SELinux is ENABLED'
else
	echo 'SELinux is DISABLED'
fi

MODE=`getenforce`
echo "Current mode: $MODE"

. /etc/selinux/config
echo "Config mode: $SELINUX"
echo ""

if [ "$IS_ROOT" != true ]; then
	exit 0
fi

case "$MODE" in
	Permissive)
	QUERY="Set Enforcing mode? y/N: "
	CMD="setenforce Enforcing"
	;;
	"Enforcing")
	QUERY="Set Permissive mode? y/N: "
	CMD="setenforce Permissive"
	;;
esac

if [[ -n "$QUERY" ]]; then
	read -p "$QUERY" ANSWER
	if [[ $ANSWER == "Y" || $ANSWER == "y" ]]; then
		`$CMD`
		echo "Current mode: `getenforce`"
		echo ""
	fi
fi

read -p "Change SELinux mode in config? y/N: " ANSWER_CONFIG
if [[ $ANSWER_CONFIG != "Y" && $ANSWER_CONFIG != "y" ]]; then
	exit 0
fi

read -p "Select SELinux mode (d - disabled, p - permissive, e - enforcing): " ANSWER_CONFIG_MODE
echo ""
case "$ANSWER_CONFIG_MODE" in
	[dD])
	CONFIG_MODE="disabled"
	;;
	[pP])
	CONFIG_MODE="permissive"
	;;
	[eE])
	CONFIG_MODE="enforcing"
	;;
	*)
	echo "Unknown mode: $ANSWER_CONFIG_MODE"
	echo "Run sudo $0 to try again"
	exit 0
	;;
esac

sed -i.bak -e 's/^SELINUX=.*$/SELINUX='"$CONFIG_MODE"'/' /etc/selinux/config 

echo "SELinux mode in config changed to $CONFIG_MODE"
echo ""
echo "To apply changes please reboot system"
echo "Source config file backuped to /etc/selinux/config.bak"
