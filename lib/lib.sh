#!/bin/bash

function die {
  echo -n -e '\e[1;31m' 1>&2
  echo "ERROR: $1" > /dev/null 1>&2
  echo -e '\e[0m' 1>&2
  exit 1
}

function print_info {
    echo -n -e '\e[1;36m'
    echo -n -e "$1"
    echo -n -e '\e[0m'
}

function print_warn {
    echo -n -e '\e[1;33m'
    echo -n -e "$1"
    echo -n -e '\e[0m'
}

function check_sanity {
   if [[ $(/usr/bin/id -u) -ne 0 ]]; then
      die 'This script must be run by root user'
   fi

   if [[ ! -f /etc/debian_version ]]; then
      die 'This distribution is not supported'
   fi
}

function check_next_value {
   argument=$1
   value=$2
   if [[ ${value} == --* ]]; then
      die "Invalid value (${value}) for argument ${argument}"
   fi
}

