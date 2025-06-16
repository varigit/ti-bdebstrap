#!/bin/sh

case $1 in

"suspend")
	# save current video format (it will be lost on suspend)
	media-ctl --get-v4l2 '"ov5640 0-003c":0' |grep -Po 'fmt:\K[^ ]*' > /tmp/ov5640_v4l2.fmt
	rmmod j721e_csi2rx
	rmmod ov5640
	;;
"resume")
	modprobe j721e_csi2rx
	modprobe ov5640
	# restore saved video format
	media-ctl --set-v4l2 '"ov5640 0-003c":0 [fmt:'$(cat /tmp/ov5640_v4l2.fmt)']'
	;;
esac

