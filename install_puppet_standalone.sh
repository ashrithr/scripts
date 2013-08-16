#!/usr/bin/env bash

# -
# Script to install standalone puppet
# -

OS=`uname -s`
REV=`uname -r`
MACH=`uname -m`

GetVersionFromFile()
{
  VERSION=`cat $1 | tr "\n" ' ' | sed s/.*VERSION.*=\ // `
}

if [ "${OS}" == "SunOS" ] ; then
  OS=Solaris
  ARCH=`uname -p`
  OSSTR="${OS} ${REV}(${ARCH} `uname -v`)"
elif [ "${OS}" == "AIX" ] ; then
  OSSTR="${OS} `oslevel` (`oslevel -r`)"
elif [ "${OS}" == "Linux" ] ; then
  KERNEL=`uname -r`
  if [ -f /usr/bin/lsb_release ] ; then
    OS=$( lsb_release -sd | tr '[:upper:]' '[:lower:]' | tr '"' ' ' | awk '{ for(i=1; i<=NF; i++) { if ( $i ~ /[0-9]+/ ) { cnt=split($i, arr, "."); if ( cnt > 1) { print arr[1] } else { print $i; } break; } print $i; } }' )
    VER=`lsb_release -sd | tr '[:upper:]' '[:lower:]' | tr '"' ' ' | awk '{ for(i=1; i<=NF; i++) { if ( $i ~ /[0-9]+/ ) { cnt=split($i, arr, "."); if ( cnt > 1) { print arr[1] } else { print $i; } break; } } }'`
  else
    OS=$( cat `ls /etc/*release | grep "redhat\|SuSE"` | head -1 | awk '{ for(i=1; i<=NF; i++) { if ( $i ~ /[0-9]+/ ) { cnt=split($i, arr, "."); if ( cnt > 1) { print arr[1] } else { print $i; } break; } print $i; } }' | tr '[:upper:]' '[:lower:]' )
    VER=`cat \`ls /etc/*release | grep "redhat\|SuSE"\` | head -1 | awk '{ for(i=1; i<=NF; i++) { if ( $i ~ /[0-9]+/ ) { cnt=split($i, arr, "."); if ( cnt > 1) { print arr[1] } else { print $i; } break; } } }' | tr '[:upper:]' '[:lower:]'`
  fi
  OS=`echo ${OS} | sed -e "s/ *//g"`
  ARCH=`uname -m`
  if [[ "xi686" == "x${ARCH}" || "xi386" == "x${ARCH}" ]]; then
    ARCH="i386"
  fi
  if [[ "xx86_64" == "x${ARCH}" || "xamd64" == "x${ARCH}" ]]; then
    ARCH="x86_64"
  fi
  OSSTR="${OS} ${VER} ${ARCH}"
elif [ "${OS}" == "Darwin" ]; then
  type -p sw_vers &>/dev/null
  [ $? -eq 0 ] && {
    OS=`sw_vers | grep 'ProductName' | cut -f 2`
    VER=`sw_vers | grep 'ProductVersion' | cut -f 2`
    BUILD=`sw_vers | grep 'BuildVersion' | cut -f 2`
    OSSTR="Darwin ${OS} ${VER} ${BUILD}"
  } || {
    OSSTR="MacOSX"
  }
fi

#Validate OS

if [[ $OSSTR =~ centos || $OSSTR =~ redhat ]]; then
  echo "[*]  RedHat based system detected"
  INSTALL="yum"
elif [[ $OSSTR =~ ubuntu ]]; then
  echo "[*] Debian based system detected"
  INSTALL="apt-get"
elif [[ $OSSTR =~ MacOSX ]]; then
  echo "[*] Mac based system detected"
else
  echo "[Error]: ${OS} is not supported"
  exit 1
fi

function install_epel_repo () {
  if [[ $OS =~ centos || $OS =~ redhat ]]; then
    if [ -f /etc/yum.repos.d/epel.repo ]; then
      echo "[*]  epel repo already exists, uisng existing epel repo"
    else
      if [ $VER = "6" ]; then
        echo "[*]  Installing epel 6 repo"
        [ ! -f /etc/yum.repos.d/epel.repo ] && rpm -ivh http://linux.mirrors.es.net/fedora-epel/6/`arch`/epel-release-6-8.noarch.rpm &> /dev/null
        [ $? -ne 0 ] && { echo "Failed installing epel repo"; }
      elif [ $VER = "5"]; then
        echo "[*]  installing epel 5 repo"
        [ ! -f /etc/yum.repos.d/epel.repo ] && rpm -ivh http://linux.mirrors.es.net/fedora-epel/5/`arch`/epel-release-5-4.noarch.rpm &> /dev/null
        [ $? -ne 0 ] && { echo "Failed installing epel repo"; }
      fi
    fi
  elif [[ ${OS} =~ ubuntu ]]; then
    echo "[*]  Performing ${INSTALL} update to refresh the repos"
    ${INSTALL} update &> /dev/null
  fi
}

function install_puppet_repo () {
  if [[ $OS =~ centos || $OS =~ redhat ]]; then
    if [ -f /etc/yum.repos.d/puppetlabs.repo ]; then
      echo "[*]  puppetlabs repo already exists, using existing puppetlabs repo"
    else
      echo "[*]  installing puppetlabs repo"
      rpm -ivh http://yum.puppetlabs.com/el/6/products/`arch`/puppetlabs-release-6-5.noarch.rpm &> /dev/null
      [ $? -ne 0 ] && { echo "Failed installing puppet repo"; exit 1; }
    fi
  elif [[ ${OS} =~ ubuntu ]]; then
    echo "[*]  installing puppetlabs repo"
    wget -q http://apt.puppetlabs.com/puppetlabs-release-precise.deb && dpkg -i puppetlabs-release-precise.deb &> /dev/null
    [ $? -ne 0 ] && { echo "Failed installing puppet repo"; exit 1; }
  else
    echo "[Fatal] Unknown OS. This script does not yet support the ${OS}, Aborting!"
    exit 2
  fi
}

install_epel_repo
install_puppet_repo
echo "[*]  Installing puppet"
${INSTALL} -y install puppet &> /dev/null
[ $? -ne 0 ] && { echo "Failed installing puppet package"; exit 1; } || echo "[*]  Sucessfully installed puppet"
