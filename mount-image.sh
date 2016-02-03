#!/bin/bash


function check_nbd {
   lsmod | grep nbd > /dev/null 2>&1
   if [[ $? -eq 1 ]]; then
      print_info 'Loading the nbd kernel module: '
      modprobe nbd > /dev/null 2>&1
      if [[ $? -eq 0 ]]; then
         print_info 'OK\n'
      else
         print_info 'FAILED\n'
         die 'Unable to load nbd kernel module!'
      fi
   else
      print_info 'nbd kernel module already loaded!\n'
   fi
}

function get_free_nbd_device {
   for dev in $(ls /dev/nbd*); 
   do
      size=$(blockdev --getsize64 ${dev})
      if [ $size -eq 0 ]; then
         echo ${dev}
         exit
      fi
   done
   die "All nbd devices are occupied!"
}

# http://www.microhowto.info/howto/connect_to_a_remote_block_device_using_nbd.html
function mount_image {
   image="$1"
   mountpoint="$2"
   partition=${3:-1}

   if [[ ! -f ${image} ]]; then
      die "${image} does not exist!"
   fi

   mkdir -p ${mountpoint}
   if [[ $? -ne 0 ]]; then
      die "Unable to create ${mountpoint}!"
   fi
   dev=$(get_free_nbd_device) 
   qemu-nbd -c ${dev} ${image}
   if [[ $? -eq 0 ]]; then
      print_info "${image} connected with ${dev}.\n"
   fi
   partprobe ${dev}
   mount ${dev}p${partition} ${mountpoint}
   if [[ $? -eq 0 ]]; then
     print_info "${dev}p${partition} mounted on ${mountpoint}.\n"
   fi
}

function usage {
   echo "Usage: $(basename $0) --image <image file> --mount <mount point> [--partition <partition>]"
   echo
   echo "    --image		path to image file"
   echo "    --mount		mountpoint for the image"
   echo "    --partition	partition number (of image) to mount (default: 1)"
   echo
}


#####################################################################
#  main 
#####################################################################

. $(dirname $0)/lib/lib.sh
check_sanity

IMAGE=""
MOUNTPOINT=""
PARTITION=1

while [[ ! -z $1 ]];
do
   if [[ "${1}" == "--image" ]]; then
      shift
      check_next_value '--image', $1
      IMAGE="${1:-}"
      shift
   elif [[ "${1}" == "--mount" ]]; then
      shift
      check_next_value '--mount', $1
      MOUNTPOINT="${1:-}"
      shift
   elif [[ "${1}" == "--partition" ]]; then
      shift
      check_next_value '--partition', $1
      PARTITION="${1:-1}"
      shift 
   else
      die "Unknown option '${1}'"
   fi
done

if [[ -z ${IMAGE} || -z ${MOUNTPOINT} ]]; then
  usage
  exit 1
fi

check_nbd
mount_image "${IMAGE}" "${MOUNTPOINT}" "${PARTITION}"
