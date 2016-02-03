#!/bin/bash


#set -x


function usage {
   echo "Usage: $(basename $0) --in <input file>"
   echo
   echo "     --in 		path to input file"
   echo
}

function copy_image {
   input="$1"

   line=$(egrep "^image" ${input} 2>/dev/null)
   [[ $? -ne 0 ]] && die "No base image specified in ${input}"   

   set $line
   image="${2:-}"
   destination="${3:-}"
  
   [[ -z ${image} ]] && die "No base image defined in the input file (${input})"
   [[ -z ${destination} ]] && die "No destination file defined for the image"

   [[ ! -f ${image} ]] && die "Base image '${image}' does not exist" 
   [[ -f ${destination} ]] && die "The destination image '${destination}' already exists! Please remove it."

   destdir="$(dirname ${destination})"
   mkdir -p ${destdir}
   [[ $? -ne 0 ]] && die "Unable to create ${destdir}!"

   cp ${image} ${destination}
   [[ $? -eq 0 ]] && echo ${destination}
}

function check_script {
   script="$1"
   which ${script} >> /dev/null
   [[ $? -eq 1 ]] && die "${script} not found. Check your PATH"
}

function check_scripts {
   check_script mount-image.sh 
   check_script umount-image.sh 
}


function generate_install_script {
   input="$1"
   install_script="$2"

   file_dir="$(dirname ${input})/files"
   echo '#!/bin/bash' > ${install_script}
   echo >> ${install_script}
   echo "echo 'exit 101' > /usr/sbin/policy-rc.d" >> ${install_script}
   echo 'chmod +x /usr/sbin/policy-rc.d' >> ${install_script}
   echo 'apt-get update' >> ${install_script}
   echo >> ${install_script}
   error_msg=""
   # write while without subshell (to retrieve error_msg outside the loop)
   while read line; do
     set $line
     [[ "${1}" == "file" ]] && parse_file "${line}" ${file_dir} ${install_script}  && continue
     [[ "${1}" == "pkg" ]] && parse_pkg "${line}" ${install_script} && continue 
     [[ "${1}" == "cmd" ]] && parse_cmd "${line}" ${install_script} && continue 
     error_msg="Unknow command: ${1}" && break
             # skip comments, 'image' lines and empty lines
   done  <<< "$(egrep -v '^#|^image|^\s*$' ${input})"

   echo "rm /usr/sbin/policy-rc.d" >> ${install_script}
   chmod +x ${install_script} || die "Error: Unable to modify permissions to ${install_script}!"
   echo ${error_msg}
}



function parse_file {
   line="$1"
   file_dir="$2"
   install_script="$3"

   set ${line}
   file=$2
   user=$3
   group=$4
   perm=$5

   
   destination_dir="$(dirname ${install_script})/files$(dirname ${file})"
   if [[ ! -d ${destination_dir} ]]; then
      mkdir -p ${destination_dir} || die "Unable to create ${destination_dir}"
   fi 
   cp ${file_dir}${file}  ${destination_dir}

   cat << EOF >> ${install_script}
if [[ ! -d \$(dirname ${file}) ]]; then
   mkdir -p  \$(dirname ${file})
   if [[ \$? -ne 0 ]]; then
      echo "Error: Could not create \$(dirname ${file})" 1>&2
      exit 1
   fi
fi
cp /tmp/files${file} ${file}
if [[ \$? -ne 0 ]]; then
   echo "Error: Could not copy ${file}!"  1>&2
   exit 1
fi
chown ${user}:${group} ${file}
if [[ \$? -ne 0 ]]; then
   echo "Error: Could not change file owner and group to ${user}:${group}!" 1>&2
   exit 1
fi
chmod ${perm} ${file}
if [[ \$? -ne 0 ]]; then
   echo "Error: Could not change permissions of ${file} to ${perm}!" 1>&2
   exit 1
fi
EOF
}

function parse_pkg {
   line="$1"
   install_script="$2"

   set ${line}
   shift    # remove 'pkg' column from line
   packages=${*:-}

   [[ -z ${packages} ]] && die "No packages specified in input file"

   cat << EOF >> ${install_script}
apt-get install -y --force-yes ${packages}
if [[ \$? -ne 0 ]]; then
   echo "Error while installing ${packages}" 1>&2
   exit 1
fi
EOF
}

function parse_cmd {
   line="$1"
   install_script="$2"

   set ${line}
   shift   # remove 'cmd' column from line
   cat << EOF >> ${install_script}
$*
if [[ \$? -ne 0 ]]; then
   echo "Error while executing: $*!" 1>&2
   exit 1
fi
EOF
}


function execute_install_script {
   mount_point="$1"
   root_install_script="$2"
   

   # Without the next line dns names will not be resolved inside the chroot
   mount -o bind /run ${mount_point}/run
   # E: Can not write log (Is /dev/pts mounted?) - openpty (2: No such file or directory
   mount -o bind /dev/pts ${mount_point}/dev/pts
   sudo chroot ${mount_point} /bin/bash -c "${root_install_script}"
   if [[ $? -ne 0 ]]; then
      umount ${mount_point}/run
      umount ${mount_point}/dev/pts
      #
      die "Install scripts "
   fi
   umount ${mount_point}/run
   umount ${mount_point}/dev/pts
   #

}

#####################################################################
# main
#####################################################################

. $(dirname $0)/lib/lib.sh
check_sanity

export PATH=$(dirname $0):$PATH
check_scripts

INPUTFILE=""

while [[ ! -z $1 ]]; 
do
   if [[ "${1}" == "--in" ]]; then
      shift
      check_next_value '--in', $1
      INPUTFILE="${1:-}"
      shift
   else
      die "Unknown option '${1}'"
   fi
done


if [[ -z ${INPUTFILE} ]]; then
   usage
   exit 1
fi

[[ ! -e ${INPUTFILE} ]] && die "${INPUTFILE} does not exist!"

print_info "Copying the base image...\n"
new_image=$(copy_image ${INPUTFILE})
[[ -z ${new_image} ]] && exit 1

mount_point="/tmp/osl_$$"
mount-image.sh --image ${new_image} --mount ${mount_point} --partition 1

install_script="${mount_point}/tmp/osl_install.sh"
error_msg=$(generate_install_script ${INPUTFILE} ${install_script}) 
[[ ! -z ${error_msg} ]] && die "${error_msg}"
execute_install_script ${mount_point}  "/tmp/osl_install.sh"


umount-image.sh ${mount_point}
[[ -d ${mount_point} ]] && rmdir ${mount_point}

