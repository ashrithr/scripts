#!/usr/bin/env bash

# ===
# Script to handle installation of chef server and client setup
#
# Description:
#  * Desc goes here
#   Supported Platforms: Redhat/CentOS/Ubuntu
#
# Author: Ashrith
# Version: 0.1
# ===

#Variables
CLR="\033[01;32m"
CLR_RED="\033[1;31m"
CLR_END="\033[0m"
IP=`ifconfig eth0 | grep 'inet addr:' | cut -d: -f2 | grep 'Bcast' | awk '{print $1}'`

#Get OS Info
OS=''
VER=''
INSTALL=''
if [ -f /usr/bin/lsb_release ] ; then
  OS=$( lsb_release -sd | tr '[:upper:]' '[:lower:]' | tr '"' ' ' | awk '{ for(i=1; i<=NF; i++) { if ( $i ~ /[0-9]+/ ) { cnt=split($i, arr, "."); if ( cnt > 1) { print arr[1] } else { print $i; } break; } print $i; } }' )
  VER=`lsb_release -sd | tr '[:upper:]' '[:lower:]' | tr '"' ' ' | awk '{ for(i=1; i<=NF; i++) { if ( $i ~ /[0-9]+/ ) { cnt=split($i, arr, "."); if ( cnt > 1) { print arr[1] } else { print $i; } break; } } }'`
else
  OS=$( cat `ls /etc/*release | grep "redhat\|SuSE"` | head -1 | awk '{ for(i=1; i<=NF; i++) { if ( $i ~ /[0-9]+/ ) { cnt=split($i, arr, "."); if ( cnt > 1) { print arr[1] } else { print $i; } break; } print $i; } }' | tr '[:upper:]' '[:lower:]' )
  VER=`cat \`ls /etc/*release | grep "redhat\|SuSE"\` | head -1 | awk '{ for(i=1; i<=NF; i++) { if ( $i ~ /[0-9]+/ ) { cnt=split($i, arr, "."); if ( cnt > 1) { print arr[1] } else { print $i; } break; } } }' | tr '[:upper:]' '[:lower:]'`
fi

OS=`echo ${OS} | sed -e "s/ *//g"`

#Get the Architecture
ARCH=`uname -m`
if [[ "xi686" == "x${ARCH}" || "xi386" == "x${ARCH}" ]]; then
  ARCH="i386"
fi
if [[ "xx86_64" == "x${ARCH}" || "xamd64" == "x${ARCH}" ]]; then
  ARCH="x86_64"
fi

#Functions
function printclr () {
  echo -e $CLR"[${USER}][`date`] - ${*}"$CLR_END
}

function printerr () {
  echo -e $CLR_RED"[${USER}][`date`] - [ERROR] ${*}"$CLR_END
}

function logit () {
  echo -e $CLR"[${USER}][`date`] - ${*}"$CLR_END
}

function install_epel_repo () {
  if [[ $OS =~ centos || $OS =~ redhat ]]; then
    if [ -f /etc/yum.repos.d/epel.repo ]; then
      logit "[DEBUG]: epel repo already exists, uisng existing epel repo"
    else
      if [ $VER = "6" ]; then
        logit "[DEBUG]: Installing epel 6 repo"
        rpm -ivh http://linux.mirrors.es.net/fedora-epel/6/`arch`/epel-release-6-8.noarch.rpm
      elif [ $VER = "5"]; then
        logit "[DEBUG]: installing epel 5 repo"
        rpm -ivh http://linux.mirrors.es.net/fedora-epel/5/`arch`/epel-release-5-4.noarch.rpm
      fi
    fi
  elif [[ ${OS} =~ ubuntu ]]; then
    logit "[DEBUG]: Performing ${INSTALL} update to refresh the repos"
    ${INSTALL} update
  fi
}

function preq () {
  preq_commands="curl"
  for cmd in $preq_commands; do
    command -v $cmd >/dev/null 2>&1 || {
      echo >&2 "I require $cmd but it's not installed. Installing $cmd ...";
        if [[ $OS =~ centos || $OS =~ redhat ]]; then
          yum -y install ${cmd}
        elif [[ ${OS} =~ ubuntu ]]; then
          apt-get -y install ${cmd}
        else
          printerr "[Fatal] Unknown OS. This script does not yet support the ${OS}, Aborting!"
          exit 2
        fi
       }
  done
}

function install_chef_repo () {
  if [[ $OS =~ centos || $OS =~ redhat ]]; then
    cat > /etc/yum.repos.d/opscode-chef.repo <<EOF
[opscode-chef]
name=Opcode Chef full-stack installers for EL6 - \$basearch
baseurl=http://yum.opscode.com/el/${VER}/\$basearch/
enabled=1
gpgcheck=1
gpgkey=http://apt.opscode.com/packages@opscode.com.gpg.key
EOF
    gpg --keyserver keys.gnupg.net --recv-keys 83EF826A
    gpg --export -a packages@opscode.com | sudo tee /etc/pki/rpm-gpg/RPM-GPG-KEY-opscode > /dev/null
    rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-opscode
    yum clean all
  elif [[ ${OS} =~ ubuntu ]]; then
    echo "deb http://apt.opscode.com/ `lsb_release -cs`-0.10 main" | sudo tee /etc/apt/sources.list.d/opscode.list
    #add opscode gpg to apt
    sudo mkdir -p /etc/apt/trusted.gpg.d
    gpg --keyserver keys.gnupg.net --recv-keys 83EF826A
    gpg --export packages@opscode.com | sudo tee /etc/apt/trusted.gpg.d/opscode-keyring.gpg > /dev/null
    sudo apt-get update
  else
    printerr "[Fatal] Unknown OS. This script does not yet support the ${OS}, Aborting!"
    exit 2
  fi
}

function install_chef_client () {
  # can install both client and workstation
  curl -L https://www.opscode.com/chef/install.sh | bash
}

#PARMS: chef_server_webui_password
function install_chef_service () {
  WEBUI_PASSWORD=$1
  MSQ_QUEUE_PASSWORD=$2
  if [[ $OS =~ centos || $OS =~ redhat ]]; then
    curl https://opscode-omnitruck-release.s3.amazonaws.com/el/6/x86_64/chef-server-11.0.6-1.el6.x86_64.rpm -o \
         /root/chef-server-11.0.6-1.el6.x86_64.rpm
    yum -y localinstall chef-server-11.0.6-1.el6.x86_64.rpm
    chef-server-ctl reconfigure
    mkdir -p ~/.chef
    cp /etc/chef-server/chef-validator.pem /etc/chef-server/chef-webui.pem ~/.chef
    chown -R $USER ~/.chef
    echo 'export PATH="/opt/chef-server/embedded/bin:$PATH"' >> ~/.bash_profile && source ~/.bash_profile
    cat > ~/.chef/knife.rb <<EOF
log_level                :info
log_location             STDOUT
node_name                'root'
client_key               '/root/.chef/root.pem'
validation_client_name   'chef-validator'
validation_key           '/root/.chef/chef-validator.pem'
chef_server_url          'https://`hostname --fqdn`'
syntax_check_cache_path  '/root/.chef/syntax_check_cache'
EOF
  elif [[ ${OS} =~ ubuntu ]]; then
    [ ${WEBUI_PASSWORD} ] || WEBUI_PASSWORD='secret123'
    [ ${MSQ_QUEUE_PASSWORD} ] || MSQ_QUEUE_PASSWORD='secret123'
    sudo debconf-set-selections <<< "chef chef/chef_server_url string http://`hostname --fqdn`:4000"
    sudo debconf-set-selections <<< "chef-server-webui chef-server-webui/admin_password password ${WEBUI_PASSWORD}"
    sudo debconf-set-selections <<< "chef-solr chef-solr/amqp_password password ${MSQ_QUEUE_PASSWORD}"
    sudo apt-get install -y opscode-keyring chef chef-server
    #Configure command line tool
    mkdir -p ~/.chef
    sudo cp /etc/chef/validation.pem /etc/chef/webui.pem ~/.chef
    sudo chown -R $USER ~/.chef
    cat > ~/.chef/knife.rb <<EOF
log_level                :info
log_location             STDOUT
node_name                'ubuntu'
client_key               '/home/ubuntu/.chef/ubuntu.pem'
validation_client_name   'chef-validator'
validation_key           '/home/ubuntu/.chef/validation.pem'
chef_server_url          'http://`hostname --fqdn`:4000'
cache_type               'BasicFile'
cache_options( :path => '/home/ubuntu/.chef/checksums' )
EOF
  #create client account
  knife client create ashrith -d -a -f /tmp/ashrith.pem
  #knife client show chef-webui
  fi
}

function stop_iptables () {
  if [[ $OS =~ centos || $OS =~ redhat ]]; then
    printclr "Stopping IPTables and Disabling SELinux"
    /etc/init.d/iptables stop
    chkconfig iptables off
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/sysconfig/selinux
    /usr/sbin/setenforce 0
    rm -f /selinux/enforce
  elif [[ ${OS} =~ ubuntu ]]; then
    printclr "Stopping IPTables"
    ufw disable
  else
    printerr "[Fatal] Unknown OS. This script does not yet support the ${OS}, Aborting!"
  exit 2
fi
}

function usage () {
script=$0
cat << USAGE
Syntax
`basename $script` -s -c -J {-Xmx512m|-Xmx256m} -H {cs_hostname} -h

-s: Chef server setup
-c: Chef client setup
-w: Chef workstation setup
-J: JVM Heap Size for solr
-H: chef server hostname (for client setup)
-h: show help

Examples:
Install puppet server with all defaults:
`basename $script` -s
Install puppet client:
`basename $script` -c -H {chef_server_hostname}

USAGE
exit 1
}

############################
#Main Logic
############################

trap "quit 3" SIGINT SIGQUIT SIGTSTP

#check number of arguments
if [ $# -eq 0 ];
then
  printerr "Arguments required"
  usage
fi

#parse command line options
while getopts j:M:S:E:H:schw opts
do
  case $opts in
    s)
    CS_SETUP=1
      ;;
    h)
    usage
      ;;
    c)
    CC_SETUP=1
      ;;
    w)
    WS_SETUP=1
    J)
    JVM_SIZE=${OPTARG}
      ;;
    H)
    CS_HN=${OPTARG}
      ;;
    \?)
    usage
      ;;
  esac
done

#Set defaults for cmd line args if not passed
if [ -z ${JVM_SIZE} ];
then
  JVM_SIZE="-Xmx192m"
fi

if [ $CS_SETUP -eq 1 ]; then
  if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root"
   exit 1
  fi
  preq
  install_epel_repo
  install_chef_repo
  stop_iptables
  install_chef_service
  if [ $? -eq 0 ]; then
    cat <<EOF
    Sucessfully installed chef-server
    Now you can bootstrap new nodes (which includes installing chef client) by using:
    * If using private key:
      - knife bootstrap FQDN_OR_IP -i PATH_TO_KEY -x USERNAME
    * If using password:
      - knife bootstrap FQDN_OR_IP -x USERNAME -P PASSWORD
    * If sudo is required:
      - knife bootstrap FQDN_OR_IP -i PATH_TO_KEY -x USERNAME --sudo
EOF
elif [ $CC_SETUP -eq 1 ]; then
  preq
  install_chef_client
elif [ $WS_SETUP -eq 1 ]; then
  preq
  install_chef_client
  cat <<EOF
  Get the following files to .chef dir:
  * For Hosted Chef: download knife.rb, ORGANIZATION-validator.pem USER.pem
  * For OpenSource Chef:
    - Create knife.rb usig `knife configure --initial`
    - Copy `chef-validator.pem` on the open source chef server (located at /etc/chef-server)
EOF
fi
