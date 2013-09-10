#!/usr/bin/env bash

# ---
# Script to install puppet in standalone mode
# Supported OS: RedHat, Debian, Darwin
# @author ashrith
# ---

OS=`uname -s`
REV=`uname -r`
MACH=`uname -m`
LOG="/tmp/puppet_install.log"

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
elif [[ $OSSTR =~ Darwin ]]; then
  echo "[*] Mac based system detected"
else
  echo "[Error]: ${OS} is not supported"
  exit 1
fi

function yesno () {
  while :
  do
    echo -e "$* (Y/N)? \c"

    read yn junk

    case $yn in
        y|Y|yes|Yes|YES)
          return 0;;
        n|N|no|No|NO)
          return 1;;
        *)
          echo Please answer Yes or No.;;
    esac
  done
}

function install_epel_repo () {
  if [[ $OS =~ centos || $OS =~ redhat ]]; then
    if [ -f /etc/yum.repos.d/epel.repo ]; then
      echo "[*]  epel repo already exists, uisng existing epel repo"
    else
      if [ $VER = "6" ]; then
        echo "[*]  Installing epel 6 repo"
        [ ! -f /etc/yum.repos.d/epel.repo ] && rpm -ivh http://linux.mirrors.es.net/fedora-epel/6/${ARCH}/epel-release-6-8.noarch.rpm > ${LOG} 2>&1
        [ $? -ne 0 ] && { echo "Failed installing epel repo"; }
      elif [ $VER = "5"]; then
        echo "[*]  installing epel 5 repo"
        [ ! -f /etc/yum.repos.d/epel.repo ] && rpm -ivh http://linux.mirrors.es.net/fedora-epel/5/${ARCH}/epel-release-5-4.noarch.rpm > ${LOG} 2>&1
        [ $? -ne 0 ] && { echo "Failed installing epel repo, error logged at: ${LOG}"; }
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
      echo "[*]  Installing puppetlabs repo"
      rpm -ivh http://yum.puppetlabs.com/el/6/products/${ARCH}/puppetlabs-release-6-5.noarch.rpm > ${LOG} 2>&1
      [ $? -ne 0 ] && { echo "Failed installing puppet repo, error logged at: ${LOG}"; exit 1; }
    fi
  elif [[ ${OS} =~ ubuntu ]]; then
    echo "[*]  installing puppetlabs repo"
    wget -q http://apt.puppetlabs.com/puppetlabs-release-precise.deb && dpkg -i puppetlabs-release-precise.deb > ${LOG} 2>&1
    [ $? -ne 0 ] && { echo "Failed installing puppet repo, error logged at: ${LOG}"; exit 1; }
  else
    echo "[Fatal] Unknown OS. This script does not yet support the ${OS}, Aborting!"
    exit 2
  fi
}

function install_puppet_mac () {
  facter_version=$1
  puppet_version=$2
  target_volume=$3

  start_date=$(date "+%Y-%m-%d%:%H:%M:%S")
  mkdir /private/tmp/$start_date && cd /private/tmp/$start_date

  curl -O http://downloads.puppetlabs.com/mac/facter-$facter_version.dmg
  curl -O http://downloads.puppetlabs.com/mac/puppet-$puppet_version.dmg

  hdiutil attach facter-$facter_version.dmg
  hdiutil attach puppet-$puppet_version.dmg

  sudo installer -package /Volumes/facter-$facter_version/facter-$facter_version.pkg -target "$target_volume"
  sudo installer -package /Volumes/puppet-$puppet_version/puppet-$puppet_version.pkg -target "$target_volume"
  
  echo "Creating directories in /var and /etc - needs sudo"
  sudo mkdir -p /var/lib/puppet
  sudo mkdir -p /etc/puppet/manifests
  sudo mkdir -p /etc/puppet/ssl

  if [ $(dscl . -list /Groups | grep puppet | wc -l)  = 0 ]; then
    echo "Creating a puppet group - needs sudo"
    max_gid=$(dscl . -list /Groups gid | awk '{print $2}' | sort -ug | tail -1) 
    new_gid=$((max_gid+1))
    sudo dscl . create /Groups/puppet
    sudo dscl . create /Groups/puppet gid $new_gid
  fi
 
 
  if [ $(dscl . -list /Users | grep puppet | wc -l)  = 0 ]; then
    echo "Creating a puppet user - needs sudo"
    max_uid=$(dscl . -list /Users UniqueID | awk '{print $2}' | sort -ug | tail -1)
    new_uid=$((max_uid+1))
    sudo dscl . create /Users/puppet
    sudo dscl . create /Users/puppet UniqueID $new_uid
    sudo dscl . -create /Users/puppet PrimaryGroupID $new_gid
  fi
 
  echo "Creating /etc/puppet/puppet.conf - needs sudo"
 
sudo sh -c "echo \"[main]
pluginsync = false
server = `hostname`
 
[master]
vardir = /var/lib/puppet
libdir = $vardir/lib
ssldir = /etc/puppet/ssl
certname = `hostname`
 
[agent]
vardir = /var/lib/puppet
libdir = $vardir/lib
ssldir = /etc/puppet/ssl
certname = `hostname`
\" > /etc/puppet/puppet.conf"
 
  echo "Changing permissions - needs sudo"
   
  sudo chown -R puppet:puppet  /var/lib/puppet
  sudo chown -R puppet:puppet  /etc/puppet
   
  echo "Cleaning up"
   
  hdiutil detach /Volumes/facter-$facter_version
  hdiutil detach /Volumes/puppet-$puppet_version
   
  cd /private/tmp
  rm -rf ./$start_date  
}

if [[ $OS =~ centos || $OS =~ redhat || ${OS} =~ ubuntu ]]; then
  install_epel_repo
  install_puppet_repo
  echo "[*]  Installing puppet"
  ${INSTALL} -y install puppet > ${LOG} 2>&1
  [ $? -ne 0 ] && { echo "Failed installing puppet package, error logged at: ${LOG}"; exit 1; } || echo "[*]  Sucessfully installed puppet"
elif [[ $OSSTR =~ Darwin  ]]; then
  if [ $# -ne 3 ]; then
    MAC_FACTER_VER=$1
    MAC_PUPPET_VER=$2
    MAC_DEFAULT_VOL=$3
  else
    echo "[*] No values specified for puppet & facter using latest pacakges"
    MAC_FACTER_VER="1.7.3"
    MAC_PUPPET_VER="3.2.4"
    MAC_DEFAULT_VOL="/Volumes/Macintosh\ HD/"
  fi
  echo "About to install Facter ${MAC_FACTER_VER} and Puppet ${MAC_PUPPET_VER} on target volume ${MAC_DEFAULT_VOL}"
  if yesno Do you really wish to quit now; then
    install_puppet_mac $MAC_FACTER_VER $MAC_PUPPET_VER $MAC_DEFAULT_VOL
  else
    echo "Exiting"
    exit 0
  fi
fi