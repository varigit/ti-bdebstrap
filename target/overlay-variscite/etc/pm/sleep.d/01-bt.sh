#!/bin/sh

[ -x /etc/bluetooth/variscite-bt ] || exit 0

SOC=`cat /sys/bus/soc/devices/soc0/soc_id`
if [ "${SOC#i.MX6UL*}" != "${SOC}" ] ; then
	if [ -d /sys/bus/platform/devices/1806000.nand-controller ] ; then
		exit 0
	fi
fi

case $1 in

"suspend")
        /etc/bluetooth/variscite-bt stop
        ;;
"resume")
        /etc/bluetooth/variscite-bt start
        ;;
esac
