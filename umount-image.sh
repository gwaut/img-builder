#!/bin/bash

function usage {
   echo "Usage: $0 <mountpoint>"
   echo "    <mountpoint>: mountpoint to unmount"   
   
}
###############################################################
#  main
###############################################################


. $(dirname $0)/lib/lib.sh

if [[ -z $1 ]]; then
   usage
   exit 1
fi

MOUNTPOINT="$1"
if [[ ! -d ${MOUNTPOINT} ]]; then
   die "${MOUNTPOINT} does not exist!"
fi

mountpoint -q ${MOUNTPOINT}
if [[ $? -ne 0 ]]; then
   die "${MOUNTPOINT} is not a  mountpoint!"
fi

# Remove trailing / from mountpoint
MOUNTPOINT=${MOUNTPOINT%/}
#echo ${MOUNTPOINT}


target=$(df --output=source,target | grep ${MOUNTPOINT} | awk '{print $1}')

#Remove partition part
target=${target%p[0-9]*}

check_sanity

umount ${MOUNTPOINT}
if [[ $? -ne 0 ]]; then
   die "Unable to umount ${MOUNTPOINT}!"
fi

qemu-nbd -d ${target}
if [[ $? -ne 0 ]]; then
   die "Unable to disconnect ${target}!"
fi
