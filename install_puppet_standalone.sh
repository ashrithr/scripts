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
 
echo $OSSTR
 
#Validate OS
 
if [[ $OSSTR =~ centos || $OSSTR =~ redhat ]]; then
  echo "[Debug]: RedHat based system detected"
  INSTALL="yum"
elif [[ $OSSTR =~ ubuntu ]]; then
  echo "[Debug]: Debian based system detected"
  INSTALL="apt-get"
elif [[ $OSSTR =~ MacOSX ]]; then
  echo "[Debug]: Mac based system detected"
else
  echo "[Error]: ${OS} is not supported"
  exit 1
fi
 
function install_epel_repo () {
  if [[ $OS =~ centos || $OS =~ redhat ]]; then
    if [ -f /etc/yum.repos.d/epel.repo ]; then
      echo "[DEBUG]: epel repo already exists, uisng existing epel repo"
    else
      if [ $VER = "6" ]; then
        echo "[DEBUG]: Installing epel 6 repo"
        rpm -ivh http://linux.mirrors.es.net/fedora-epel/6/`arch`/epel-release-6-8.noarch.rpm
      elif [ $VER = "5"]; then
        echo "[DEBUG]: installing epel 5 repo"
        rpm -ivh http://linux.mirrors.es.net/fedora-epel/5/`arch`/epel-release-5-4.noarch.rpm
      fi
    fi
  elif [[ ${OS} =~ ubuntu ]]; then
    echo "[DEBUG]: Performing ${INSTALL} update to refresh the repos"
    ${INSTALL} update
  fi
}
 
function install_puppet_repo () {
  if [[ $OS =~ centos || $OS =~ redhat ]]; then
    echo "[DEBUG]: installing puppetlabs repo"
    rpm -ivh http://yum.puppetlabs.com/el/6/products/`arch`/puppetlabs-release-6-5.noarch.rpm
  elif [[ ${OS} =~ ubuntu ]]; then
    echo "[DEBUG]: installing puppetlabs repo"
    wget http://apt.puppetlabs.com/puppetlabs-release-precise.deb && dpkg -i puppetlabs-release-precise.deb
  else
    echo "[Fatal] Unknown OS. This script does not yet support the ${OS}, Aborting!"
    exit 2
  fi
}
 
install_epel_repo
install_puppet_repo
${INSTALL} -y install puppet
