#!/usr/bin/env bash

# ===
# Script to handle puppet server and client setup with puppetdb, sed
#
# Description:
#   * Installs puppet server
#   * Installs puppet client
#   * Installs puppetdb for stored configs
#   * Installs passenger for scaling puppet server
#   * Installs postgresql for puppetdb (dependency)
#   * Sets up autosigning for the machines in same domain as puppet server
#   Supported Platforms: Redhat/CentOS/Ubuntu
#
# Sample Usage:
#   * ./puppetinstaller.sh -h
#
# Author: Ashrith
# Version: 1.6
# ===

#Variables
CLR="\033[01;32m"
CLR_RED="\033[1;31m"
CLR_END="\033[0m"
PUPPET_SERVER=`hostname --fqdn`
HOSTNAME=`uname -n | cut -d . -f 1`
DOMAIN_NAME=`echo $PUPPET_SERVER | cut -d "." -f 2-`
IP=`ifconfig eth0 | grep 'inet addr:' | cut -d: -f2 | grep 'Bcast' | awk '{print $1}'`

#Get OS Info
OS=''
VER=''
INSTALL=''
if [ -f /usr/bin/lsb_release ] ; then
  OS=$( lsb_release -sd | tr '[:upper:]' '[:lower:]' | tr '"' ' ' | awk '{ for(i=1; i<=NF; i++) { if ( $i ~ /[0-9]+/ ) { cnt=split($i, arr, "."); if ( cnt > 1) { print arr[1] } else { print $i; } break; } print $i; } }' )
  VER=$( lsb_release -sd | tr '[:upper:]' '[:lower:]' | tr '"' ' ' | awk '{ for(i=1; i<=NF; i++) { if ( $i ~ /[0-9]+/ ) { cnt=split($i, arr, "."); if ( cnt > 1) { print arr[1] } else { print $i; } break; } } }')
else
  OS=$( cat `ls /etc/*release | grep "redhat\|SuSE"` | head -1 | awk '{ for(i=1; i<=NF; i++) { if ( $i ~ /[0-9]+/ ) { cnt=split($i, arr, "."); if ( cnt > 1) { print arr[1] } else { print $i; } break; } print $i; } }' | tr '[:upper:]' '[:lower:]' )
  VER=$( cat `ls /etc/*release | grep "redhat\|SuSE"` | head -1 | awk '{ for(i=1; i<=NF; i++) { if ( $i ~ /[0-9]+/ ) { cnt=split($i, arr, "."); if ( cnt > 1) { print arr[1] } else { print $i; } break; } } }' | tr '[:upper:]' '[:lower:]')
fi

OS=$( echo ${OS} | sed -e "s/ *//g")

#Get the Architecture
ARCH=`uname -m`
if [[ "xi686" == "x${ARCH}" || "xi386" == "x${ARCH}" ]]; then
  ARCH="i386"
fi
if [[ "xx86_64" == "x${ARCH}" || "xamd64" == "x${ARCH}" ]]; then
  ARCH="x86_64"
fi

#Add os specific packages
if [[ $OS =~ centos || $OS =~ redhat ]]; then
  INSTALL="yum"
  PUPPETPKG="puppet-server"
  APACHEPKG=httpd
  PUPPETDAEMON="puppetmaster"
  PSQL_CONFIG="/var/lib/pgsql/data/pg_hba.conf"
  PSQL_DATA_CONF="/var/lib/pgsql/data/postgresql.conf"
  PUPPETDB_DEFAULT="/etc/sysconfig/puppetdb"
  PASSENGER_CONF_PATH="/etc/httpd/conf.d/puppet.conf"
  RUBY_PATH="/usr/lib/ruby"
  RUBY_EXEC="/usr/bin/ruby"
elif [[ ${OS} =~ ubuntu ]]; then
  INSTALL="apt-get"
  PUPPETPKG="puppetmaster"
  APACHEPKG=apache2
  PUPPETDAEMON="puppetmaster"
  PSQL_CONFIG="/etc/postgresql/9.1/main/pg_hba.conf"
  PSQL_DATA_CONF="/etc/postgresql/9.1/main/postgresql.conf"
  PUPPETDB_DEFAULT="/etc/default/puppetdb"
  PASSENGER_CONF_PATH="/etc/apache2/sites-available/puppetmasterd"
  RUBY_PATH="/var/lib"
  RUBY_EXEC="/usr/bin/ruby1.8"
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

function install_puppet_repo () {
  if [[ $OS =~ centos || $OS =~ redhat ]]; then
    logit "[DEBUG]: installing puppetlabs repo"
    rpm -ivh http://yum.puppetlabs.com/el/6/products/`arch`/puppetlabs-release-6-5.noarch.rpm
  elif [[ ${OS} =~ ubuntu ]]; then
    logit "[DEBUG]: installing puppetlabs repo"
    wget http://apt.puppetlabs.com/puppetlabs-release-precise.deb && dpkg -i puppetlabs-release-precise.deb
    apt-get update
  else
    printerr "[Fatal] Unknown OS. This script does not yet support the ${OS}, Aborting!"
    exit 2
  fi
}

function disable_gpgcheck () {
  if [[ $OS =~ centos || $OS =~ redhat ]]; then
    local files="epel.repo puppetlabs.repo epel-testing.repo"
    for f in ${files}; do
      sed -i 's/gpgcheck=1/gpgcheck=0/' /etc/yum.repos.d/${f}
    done
    yum clean all &> /dev/null
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

function install_postgres () {
  printclr "Installing Postgresql"
  if [[ $OS =~ centos || $OS =~ redhat ]]; then
    ${INSTALL} -y install postgresql postgresql-server postgresql-devel
    [ $? -ne 0 ] && ( printerr "[Fatal]: Falied to install postgresql" && exit 2 ) || ( printclr "Installing Postgresql Suceeded" )
    service postgresql initdb
    ( service postgresql start ) && ( chkconfig postgresql on )
  elif [[ ${OS} =~ ubuntu ]]; then
    ${INSTALL} -y install postgresql libpq-dev
    [ $? -ne 0 ] && ( printerr "[Fatal]: Falied to install postgresql" && exit 2 ) || ( printclr "Installing Postgresql Suceeded" )
  fi
  printclr "Creating postgresql users and databases"
  cat > ${PSQL_CONFIG} <<\PSQLDELIM
# TYPE  DATABASE    USER        CIDR-ADDRESS          METHOD
local all all trust
host all all 127.0.0.1/32 trust
host all all ::1/128 trust
host puppetdb puppetdb 0.0.0.0/0 trust
PSQLDELIM
  echo "listen_addresses = '0.0.0.0'" >> ${PSQL_DATA_CONF}
  printclr "[Debug]: Setting up postgresql for puppetdb and hsmp"
  service postgresql restart #restart postgresql to take effects
  psql -U postgres -d template1 <<\END
create user puppetdb with password 'puppetdb';
create database puppetdb with owner puppetdb;
END
}

function usage () {
script=$0
cat << USAGE
Syntax
`basename ${script}` -s -c -J {-Xmx512m|-Xmx256m} -P {psql_password} -H {ps_hostname} -h

-s: puppet server setup
-c: puppet client setup
-J: JVM Heap Size for puppetdb
-P: postgresql password for puppetdb user
-H: puppet server hostname | mcollective sever hostname (for client setup)
-h: show help

Examples:
Install puppet server with all defaults:
`basename $script` -s
Install puppet client:
`basename $script` -c -H {puppet_server_hostname}

USAGE
exit 1
}

function quit () {
  code=$1
  printclr "cleaning up..."
  PUPPET_PKGS="puppet puppetdb"
  GEMS_REMOVE="passenger"
  DIRS_REMOVE="/etc/puppet /var/lib/puppet /var/log/puppet /var/log/puppetdb /etc/puppetdb"
  for PKG in ${PUPPET_PKGS}; do
    type -P ${PKG} && ${INSTALL} -y remove ${PKG}
  done
  for DIR in ${DIRS_REMOVE}; do
    [ -d ${DIR} ] && rm -rf ${DIR}
  done
  #check fif rubygems is intalled
  rpm -qa | grep gem &>/dev/null
  if [ $? -eq 0 ]; then
    #remove gems
    for GEM in ${GEMS_REMOVE}; do
      gem list | grep ${GEM} &>/dev/null
      [ $? -eq 0 ] && ( gem uninstall -aIx ${GEM} ) || echo "gem ${GEM} not present"
    done
  fi
  exit $code
}

############################
#Main Logic
############################

trap "quit 3" SIGINT SIGQUIT SIGTSTP

#only root can run this script
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root"
   exit 1
fi

#check number of arguments
if [ $# -eq 0 ];
then
  printerr "Arguments required"
  usage
fi

#parse command line options
while getopts j:M:S:E:P:H:schmd opts
do
  case $opts in
    s)
    PS_SETUP=1
      ;;
    h)
    usage
      ;;
    c)
    PC_SETUP=1
      ;;
    J)
    JVM_SIZE=${OPTARG}
      ;;
    P)
    PSQL_PWD=${OPTARG}
      ;;
    H)
    PS_MC_HN=${OPTARG}
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

if [ -z ${PSQL_PWD} ];
then
  PSQL_PWD="puppetdb"
fi

#Manage Repos
install_epel_repo
install_puppet_repo
disable_gpgcheck
stop_iptables
if [[ $OS =~ centos || $OS =~ redhat ]]; then
  yum clean all
fi

#puppet server setup
if [ "$PS_SETUP" == "1" ]; then

  #install postgresql
  install_postgres

  printclr "Installing puppet server packages"
  ${INSTALL} -y install ${PUPPETPKG} puppet
  if [ $? -ne 0 ]; then
    printerr "failed installing puppet"
    exit 2
  fi
  #Dir structure and permissions
  printclr "Creating required dir structure"
  mkdir -p /var/lib/puppet/ssl
  chown puppet.puppet /var/lib/puppet/ssl
  mkdir -p /etc/puppet/rack/{public,tmp}
  mkdir -p /etc/puppet/enc
  chown -R puppet /etc/puppet/rack
  chmod -R 755 /etc/puppet/rack
  if [[ ${OS} =~ centos || ${OS} =~ redhat ]]; then
    if [ -f /usr/share/puppet/ext/rack/config.ru ]; then
      cp /usr/share/puppet/ext/rack/config.ru /etc/puppet/rack
    elif [ -f /usr/share/puppet/ext/rack/files/config.ru ]; then
      cp /usr/share/puppet/ext/rack/files/config.ru /etc/puppet/rack
    else
      echo "Cannot find 'config.ru' file, trying to download file from puppet source"
      cd /tmp && wget http://downloads.puppetlabs.com/puppet/puppet-3.1.1.tar.gz
      tar -xzf puppet-3.1.1.tar.gz
      cp puppet-3.1.1/ext/rack/files/config.ru /etc/puppet/rack
      rm -rf /tmp/puppet*
    fi
  elif [[ ${OS} =~ ubuntu ]]; then
    cd /tmp && wget http://downloads.puppetlabs.com/puppet/puppet-3.1.1.tar.gz
    tar -xzf puppet-3.1.1.tar.gz
    cp puppet-3.1.1/ext/rack/files/config.ru /etc/puppet/rack
    rm -rf /tmp/puppet*
  fi
  chown puppet /etc/puppet/rack/config.ru
  ln -s /var/lib/puppet/ssl /etc/puppet/ssl

  #start puppet services if not using apache passenger
  #puppet resource service puppet ensure=running enable=true
  #puppet resource service puppetmaster ensure=running enable=true

cat > /etc/puppet/puppet.conf << END
[main]
  logdir = /var/log/puppet
  rundir = /var/run/puppet
  ssldir = \$vardir/ssl
  server = PUPPET_SERVER_PH

[agent]
  classdir = \$vardir/classes.txt
  localconfig = \$vardir/localconfig

[master]
  ssl_client_header = SSL_CLIENT_S_DN
  ssl_client_verify_header = SSL_CLIENT_VERIFY
END

sed -e s,PUPPET_SERVER_PH,${PUPPET_SERVER},g -i /etc/puppet/puppet.conf

#Setup Autosigning
echo "*.${DOMAIN_NAME}" > /etc/puppet/autosign.conf

  #run puppet once without passenger, required for generating initial certificates.
  printclr "Intializing puppetmaster run for generating certificates"
  if [[ $OS =~ centos || $OS =~ redhat ]]; then
    /etc/init.d/puppetmaster start
    /etc/init.d/puppetmaster stop
  elif [[ ${OS} =~ ubuntu ]]; then
    service puppetmaster stop
  fi
  chmod g+w /var/lib/puppet/ssl/ca/private/*
  chmod g+w /var/lib/puppet/ssl/ca/ca*pem

  #create hiera.yaml
cat > /etc/puppet/hiera.yaml <<\HIERADELIM
---
:hierarchy:
 - %{operatingsystem}
 - common
:backends:
 - yaml
:yaml:
 :datadir: '/etc/puppet/environments/%{environment}/hieradata'
HIERADELIM
#######################
#Passenger Setup
#######################
printclr "Installing dependecies for passenger"
if [[ $OS =~ centos || $OS =~ redhat ]]; then
  yum -y install httpd httpd-devel ruby-devel rubygems mod_ssl.x86_64 curl-devel openssl-devel gcc-c++ zlib-devel make
  rm -rf /etc/httpd/conf.d/ssl.conf
  rm -rf /etc/httpd/conf.d/welcome.conf
  chkconfig httpd on
elif [[ ${OS} =~ ubuntu ]]; then
  apt-get -y install apache2 ruby1.8-dev rubygems libcurl4-openssl-dev libssl-dev zlib1g-dev apache2-prefork-dev libapr1-dev libaprutil1-dev
  a2enmod ssl
  a2enmod headers
  update-rc.d -f puppetmaster remove  #making sure puppetmaster does not start using init scripts
fi
printclr "Installing gems required for passenger"
gem install --no-rdoc --no-ri rack
gem install --no-rdoc --no-ri passenger --version=3.0.18
if [[ $OS =~ centos || $OS =~ redhat ]]; then
  /usr/bin/passenger-install-apache2-module -a
elif [[ ${OS} =~ ubuntu ]]; then
  /usr/local/bin/passenger-install-apache2-module -a
fi
printclr "Configuring passenger"
#passenger conf file for puppet
cat > ${PASSENGER_CONF_PATH} << DELIM
# you probably want to tune these settings
PassengerHighPerformance on
PassengerMaxPoolSize 12
PassengerPoolIdleTime 1500
# PassengerMaxRequests 1000
PassengerStatThrottleRate 120
RackAutoDetect Off
RailsAutoDetect Off

Listen 8140

<VirtualHost *:8140>
        LoadModule passenger_module ${RUBY_PATH}/gems/1.8/gems/passenger-3.0.18/ext/apache2/mod_passenger.so
        PassengerRoot ${RUBY_PATH}/gems/1.8/gems/passenger-3.0.18
        PassengerRuby ${RUBY_EXEC}
        LoadModule ssl_module modules/mod_ssl.so

        SSLEngine on
        SSLProtocol -ALL +SSLv3 +TLSv1
        SSLCipherSuite ALL:!ADH:RC4+RSA:+HIGH:+MEDIUM:-LOW:-SSLv2:-EXP

        SSLCertificateFile      /etc/puppet/ssl/certs/PUPPET_SERVER_PH.pem
        SSLCertificateKeyFile   /etc/puppet/ssl/private_keys/PUPPET_SERVER_PH.pem
        SSLCertificateChainFile /etc/puppet/ssl/ca/ca_crt.pem
        SSLCACertificateFile    /etc/puppet/ssl/ca/ca_crt.pem
        # If Apache complains about invalid signatures on the CRL, you can try disabling
        # CRL checking by commenting the next line, but this is not recommended.
        SSLCARevocationFile     /etc/puppet/ssl/ca/ca_crl.pem
        SSLVerifyClient optional
        SSLVerifyDepth  1
        SSLOptions +StdEnvVars

        # This header needs to be set if using a loadbalancer or proxy
        RequestHeader unset X-Forwarded-For

        RequestHeader set X-SSL-Subject %{SSL_CLIENT_S_DN}e
        RequestHeader set X-Client-DN %{SSL_CLIENT_S_DN}e
        RequestHeader set X-Client-Verify %{SSL_CLIENT_VERIFY}e

        DocumentRoot /etc/puppet/rack/public/
        RackBaseURI /
        <Directory /etc/puppet/rack/>
                Options None
                AllowOverride None
                Order allow,deny
                allow from all
        </Directory>
</VirtualHost>
DELIM
sed -i "s/PUPPET_SERVER_PH/${PUPPET_SERVER}/g" ${PASSENGER_CONF_PATH}

  #restart httpd and check if puppet is handled by passenger
  printclr "Restarting httpd and verifying puppet run using passenger"
  if [[ ${OS} =~ ubuntu ]]; then
    a2ensite puppetmasterd  #enable the site puppetmasted
    service ${APACHEPKG} restart
  else
    service ${APACHEPKG} start
  fi

  netstat -plunt | grep 8140 &> /dev/null
  if [ $? -eq 0 ]; then
    printclr "Puppet master is running through passenger..."
  else
    printerr "Puppet master is not running somthing went wrong with apache passenger loading."
  fi
  passenger-status | grep PID | sort

  printclr "Testing puppet agent run with apche passenger:"
  puppet agent --test
  [ $? -eq 0 ] && printclr "Puppet agent run suceeded" || printerr "Puppet agent run failed"

  #######################
  #PUPPETDB Setup
  #######################
  printclr "Setting up PUPPETDB for stored configurations"
  if [[ $OS =~ centos || $OS =~ redhat ]]; then
    yum -y install puppetdb puppetdb-terminus
  elif [[ ${OS} =~ ubuntu ]]; then
    apt-get -y install puppetdb puppetdb-terminus
  fi
#configure jvm heapsize for puppetdb
cat > ${PUPPETDB_DEFAULT} <<\PUPPETDBDELIM
###########################################
# Init settings for puppetdb
###########################################

# Location of your Java binary (version 6 or higher)
JAVA_BIN="/usr/bin/java"

# Modify this if you'd like to change the memory allocation, enable JMX, etc
JAVA_ARGS="JAVAHEAPSIZE_PH -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/var/log/puppetdb/puppetdb-oom.hprof "

# These normally shouldn't need to be edited if using OS packages
USER="puppetdb"
INSTALL_DIR="/usr/share/puppetdb"
CONFIG="/etc/puppetdb/conf.d"
PUPPETDBDELIM
sed -e s,JAVAHEAPSIZE_PH,${JVM_SIZE},g -i ${PUPPETDB_DEFAULT}

#check to see if psql is allwoing connections
#psql -h localhost puppetdb puppetdb

cat > /etc/puppetdb/conf.d/database.ini <<\PUPPETDBDELIM
[database]
# For the embedded DB: org.hsqldb.jdbcDriver
# For PostgreSQL: org.postgresql.Driver
# Defaults to embedded DB
classname = org.postgresql.Driver

# For the embedded DB: hsqldb
# For PostgreSQL: postgresql
# Defaults to embedded DB
subprotocol = postgresql

# For the embedded DB: file:/path/to/database;hsqldb.tx=mvcc;sql.syntax_pgs=true
# For PostgreSQL: //host:port/databaseName
# Defaults to embedded DB located in <vardir>/db
subname = //localhost:5432/puppetdb

# Connect as a specific user
username = puppetdb

# Use a specific password
password = PASSWORD_PH

# How often (in minutes) to compact the database
# gc-interval = 60

# Number of seconds before any SQL query is considered 'slow'; offending
# queries will not be interrupted, but will be logged at the WARN log level.
log-slow-statements = 10
PUPPETDBDELIM
sed -e s,PASSWORD_PH,${PSQL_PWD},g -i /etc/puppetdb/conf.d/database.ini

#Configure Jetty to listen on 8085 and ssl on 8086
sed -i s/port\ \=\ 8080/port\ \=\ 8085/g  /etc/puppetdb/conf.d/jetty.ini
sed -i s/ssl-port\ \=\ 8081/ssl-port\ \=\ 8086/g  /etc/puppetdb/conf.d/jetty.ini

#install plugin to connect puppet master to puppetdb
printclr "Configuring puppet terminus"

cat > /etc/puppet/puppetdb.conf << DELIM
[main]
server = ${PUPPET_SERVER}
port = 8086
DELIM

echo "  storeconfigs = true
  storeconfigs_backend = puppetdb
  modulepath = \$confdir/environments/\$environment/modules:\$confdir/modules
  manifest = \$confdir/environments/\$environment/site.pp" >> /etc/puppet/puppet.conf

#This will make PuppetDB the authoritative source for the inventory service.
cat > /etc/puppet/routes.yaml <<\DELIM
---
master:
 facts:
  terminus: puppetdb
  cache: yaml
DELIM

#puppetdb ssl configuration script
puppetdb-ssl-setup

printclr "Starting puppetdb"
service puppetdb start
if [ $? -eq 0 ]; then
  printclr "puppetdb started sucessfully"
else
  printerr "puppetdb failed to start, check /var/log/puppetdb/ for logs"
fi

#logic to check if puppetdb has started listening
printclr "Pausing till puppetdb is listening"
while : ; do
 grep "Started SslSelectChannelConnector@" /var/log/puppetdb/puppetdb.log &>/dev/null && break
 printf .
 sleep 1
done
echo ""
printclr "test puppet agent run to test if setup was ok"
puppet agent -t && printclr "puppet run suceeded" || printerr "puppet agent run failed"

service ${APACHEPKG} restart #reload configurations
if [ $? -ne 0 ]; then
  echo "[Fatal]: Failed to restart passenger" 1>&2
  exit 2
fi
fi #puppet server setup end

#AGENT SETUP
if [ "$PC_SETUP" == "1" ]; then
  if [ -z "${PS_MC_HN}" ]; then
    echo -e "enter the hostname of puppet_server: \c"
    read PS_MC_HN
  fi
  ping -c1 -w1 ${PS_MC_HN} &>/dev/null
  if [ $? -eq 0 ]; then
    echo ${PS_MC_HN} is up ...
  else
    printclr "${PS_MC_HN} is down!, Aborting."
    exit 1
  fi
  printclr "Installing Puppet client"
  if [ "$OS" == "CentOS" ] || [ "$OS" == "RedHat" ]; then
    ${INSTALL} clean all
  fi
  ${INSTALL} -y install puppet
  if [ $? -ne 0 ]; then
    printerr "puppet agnet installation failed"
    exit 2
  fi
cat > /etc/puppet/puppet.conf <<\END
[main]
 logdir = /var/log/puppet
 rundir = /var/run/puppet
 ssldir = $vardir/classes.txt
[agent]
 classdir = $vardir/classes.txt
 localconfig = $vardir/localconfig
 server = PUPPETSERVER_PH
 pluginsync = true
END
sed -e s,PUPPETSERVER_PH,${PS_MC_HN},g -i /etc/puppet/puppet.conf

#printclr "Setting up cron job to start puppet agent"
#puppet resource cron puppet-agent ensure=present user=root minute=30 command='/usr/bin/puppet agent --onetime --no-daemonize --splay'

printclr "Done Installing/Configurig Puppet"
fi  #end agent setup
