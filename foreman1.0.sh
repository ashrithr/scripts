#!/bin/bash
# ===
# Script to setup foreman
#                 foreman smart-proxy for provisioning
#                 puppet
#                 passenger to scale puppet
#                 puppet stored-configs using mysql
# Thos script only works on CentOS
# Author: Ashrith
# ===
#VARIABLES Declaration
PUPPET_SERVER=`uname -n`
HOSTNAME=`uname -n | cut -d . -f 1`
DOMAIN_NAME=`echo $PUPPET_SERVER | cut -d . -f 2,3`
IP=`ifconfig eth0 | grep 'inet addr:' | cut -d: -f2 | grep 'Bcast' | awk '{print $1}'`  #get the current ip add
IP_LAST_OCTECT=`echo $IP | cut -d . -f 4`
LOG=/tmp/`basename $0`.log
CLR="\033[01;32m"
CLR_END="\033[0m"

#FUNCTIONS Declaration
function usage () {
script=$0
cat << USAGE
Syntax
`basename $script` -s -c -h

-s: puppet server setup
-c: puppet client setup
-h: show help

USAGE
exit 1
}

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
                        echo "Please enter Yes or No.";;
        esac
done
}

function logit () {
  echo "[${USER}][`date`] - ${*}" >> $LOG
}

function junkline () {
  echo "-----------------------------------------------------"
}

function jline () {
        local myvar=$1
        local length=${#myvar}
        echo $1
        for (( i=0; i <= $length; i++ ))
        do
                printf "-"
        done
        echo ""
}

function progress_ind {
  chars=( "-" "\\" "|" "/" )
  interval=1
  count=0

  while true
  do
    pos=$(($count % 4))

    echo -en "\b${chars[$pos]}"

    count=$(($count + 1))
    sleep $interval
  done
}

function stop_progress_ind () {
exec 2>/dev/null
kill $1
echo -en "\n"
}

function quit () {
  code=$1
  if yesno "Do you really want to exit ?"
  then
    echo "exiting..."
    exit $code
  else
    echo "continuing..."
  fi
}

trap "stop_progress_ind $pid; exit" INT TERM EXIT

trap "quit 3" SIGINT SIGQUIT SIGTSTP

#==========
#MAIN Logic
#==========

#TODO: CHECK HOSTS FILE
#      CHECK UNAME OF SERVER

#only root user can run the script
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root"
   exit 1
fi

#parse command line options
while getopts sch opts
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
    \?)
    usage
      ;;
  esac
done


if yesno "Do you want to stop iptables and disable selinux"
then
  /etc/init.d/iptables stop
  chkconfig iptables off
  sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/sysconfig/selinux
  /usr/sbin/setenforce 0 >> $LOG 2>&1
else
  jline "adding iptables rules required for puppet, foreman and foreman-proxy"
  #IPTables configuration
cat > /etc/sysconfig/iptables << EOF
# Firewall configuration written by system-config-firewall
# Manual customization of this file is not recommended.
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
-A INPUT -p icmp -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A INPUT -m state --state NEW -m tcp -p tcp --dport 22 -j ACCEPT
-A INPUT -m state --state NEW -m tcp -p tcp --dport 80 -j ACCEPT
-A INPUT -m state --state NEW -m tcp -p tcp --dport 443 -j ACCEPT
-A INPUT -m state --state NEW -m tcp -p tcp --dport 8140 -j ACCEPT
-A INPUT -m state --state NEW -m tcp -p tcp --dport 61613 -j ACCEPT
-A INPUT -j REJECT --reject-with icmp-host-prohibited
-A FORWARD -j REJECT --reject-with icmp-host-prohibited
COMMIT
EOF
# Enable IPTables ruleset
echo "restarting iptables ..."
service iptables restart
fi

#Install required repositories for puppet, foreman
if [ ! -f /etc/yum.repos.d/epel.repo ]
then
  jline "Installing epel repo..."
  rpm -ivh http://linux.mirrors.es.net/fedora-epel/6/`arch`/epel-release-6-7.noarch.rpm
fi
if [ ! -f /etc/yum.repos.d/puppetlabs.repo ]
then
  jline "Installing puppetlabs repo..."
  rpm -ivh http://yum.puppetlabs.com/el/6/products/`arch`/puppetlabs-release-6-5.noarch.rpm
fi
if [ ! -f /etc/yum.repos.d/foreman.repo ]
then
  jline "Installing foreman 1.0 repo..."
  rpm -ivh http://yum.theforeman.org/releases/1.0/el6/foreman-release.rpm
fi
#yum clean all

if [ "$PS_SETUP" == "1" ]
then
  jline "Installing Required Packages"
  yum install -y httpd mysql-devel.x86_64 mysql-server mysql mod_ssl.x86_64 ruby-devel.x86_64 httpd httpd-devel vsftpd ruby.x86_64 ruby-augeas.x86_64 ruby-libs.x86_64 rubygems rubygem-rails ruby-mysql rubygem-sqlite3-ruby gcc-c++ curl-devel openssl-devel zlib-devel puppet puppet-server foreman foreman-proxy foreman-mysql foreman-mysql2 foreman-libvirt ruby-augeas.x86_64 augeas.x86_64 augeas-libs.x86_64 ruby-shadow.x86_64 rrdtool-ruby graphviz git

if [ ! -f /etc/yum.repos.d/passenger.repo ]
then
  yum install -y http://passenger.stealthymonkeys.com/rhel/6/passenger-release.noarch.rpm
fi
  yum install -y mod_passenger

  jline "creating dir structure required"
  mkdir -p /var/lib/puppet/ssl
  chown puppet.puppet /var/lib/puppet/ssl
  mkdir -p /etc/puppet/rack/{public,tmp}
  chown -R puppet /etc/puppet/rack
  chmod -R 755 /etc/puppet/rack
  cp /usr/share/puppet/ext/rack/files/config.ru /etc/puppet/rack
  chown puppet /etc/puppet/rack/config.ru
  ln -s /var/lib/puppet/ssl /etc/puppet/ssl

  jline "intializing puppetmaster run for generating certificates"
  /etc/init.d/puppetmaster start
  /etc/init.d/puppetmaster stop
  chmod g+w /var/lib/puppet/ssl/ca/private/*
  chmod g+w /var/lib/puppet/ssl/ca/ca*pem

############################################
#Setting up Apache with Passenger and Puppet
############################################

#Configuration files
  jline "Building puppet conf"
  echo "*.${DOMAIN_NAME}" > /etc/puppet/autosign.conf

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

rm -rf /etc/httpd/conf.d/{ssl,welcome}.conf

jline "Building puppet passenger conf"
cat > /etc/httpd/conf.d/puppet.conf << DELIM
Listen 8140
<VirtualHost *:8140>
	LoadModule ssl_module modules/mod_ssl.so
	SSLEngine on
	SSLCipherSuite SSLv2:-LOW:-EXPORT:RC4+RSA
	SSLCertificateFile      /var/lib/puppet/ssl/certs/PUPPET_SERVER_PH.pem
	SSLCertificateKeyFile   /var/lib/puppet/ssl/private_keys/PUPPET_SERVER_PH.pem
	SSLCertificateChainFile /var/lib/puppet/ssl/ca/ca_crt.pem
	SSLCACertificateFile    /var/lib/puppet/ssl/ca/ca_crt.pem
	# CRL checking should be enabled; if you have problems with Apache complaining about the CRL, disable the next line
#	SSLCARevocationFile     /var/lib/puppet/ssl/ca/ca_crl.pem
	SSLVerifyClient optional
	SSLVerifyDepth  1
	SSLOptions +StdEnvVars

	# The following client headers allow the same configuration to work with Pound.
	RequestHeader set X-SSL-Subject %{SSL_CLIENT_S_DN}e
	RequestHeader set X-Client-DN %{SSL_CLIENT_S_DN}e
	RequestHeader set X-Client-Verify %{SSL_CLIENT_VERIFY}e

	RackAutoDetect On
  DocumentRoot /etc/puppet/rack/public/
  <Directory /etc/puppet/rack>
		Options None
		AllowOverride None
		Order allow,deny
		allow from all
	</Directory>
</VirtualHost>
DELIM
sed -i "s/PUPPET_SERVER_PH/${PUPPET_SERVER}/g" /etc/httpd/conf.d/puppet.conf

#restart httpd and check if puppet is handled by passenger
/etc/init.d/httpd restart
chkconfig httpd on
netstat -plunt | grep 8140
if [ $? -eq 0 ]
then
  echo "puppet master is running through passenger..."
else
  echo "puppet master is not running somthing went wrong with apache passenger loading."
fi

jline "Testing puppet agent run with apche passenger:"
puppet agent --test
if [ $? -eq 0 ]
then
  echo "puppet agent run suceeded"
else
  echo "puppet agent run failed"
fi

######################################################
#Setting up Puppet Stored Configurations using puppet
######################################################
# Configure MySQL
jline "Configuring MySQL"
chkconfig mysqld on && service mysqld start
read -s -p "Enter the root mysql password: " MYSQL_PASSWORD
mysqladmin -u root password ${MYSQL_PASSWORD}
mysql -u root -p${MYSQL_PASSWORD} -e "CREATE DATABASE puppet;"
mysql -u root -p${MYSQL_PASSWORD} -e "GRANT ALL PRIVILEGES ON puppet.* TO 'puppet'@'localhost' IDENTIFIED BY 'puppet';"
mysql -u root -p${MYSQL_PASSWORD} -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';"


#updating puppet conf to use mysql stored configurations
jline "Re-Building Puppet conf to accomodate stored-configurations"
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
  storeconfigs = true
  dbadapter = mysql
  dbuser = puppet
  dbpassword = puppet
  dbserber = localhost
  dbsocket = /var/lib/mysql/mysql.sock

END

sed -e s,PUPPET_SERVER_PH,${PUPPET_SERVER},g -i /etc/puppet/puppet.conf

#restart mysql, httpd and check if puppet is using mysql
/etc/init.d/mysqld restart
/etc/init.d/httpd restart
puppet agent --test
echo "Displaying mysql puppet database to check if mysql is used by puppet"
mysql -u root -p{MYSQL_PASSWORD} puppet -e "select * from hosts;"


######################################################
#Setting up FOREMAN using PASSENGER
######################################################
jline "Configuring MySQL for FOREMAN"
mysql -u root -p${MYSQL_PASSWORD} -e "CREATE DATABASE foreman;"
mysql -u root -p${MYSQL_PASSWORD} -e "GRANT ALL PRIVILEGES ON foreman.* TO 'foreman'@'localhost' IDENTIFIED BY 'foreman';"


#Foreman configuration files
cat > /etc/foreman/database.yml << DELIM
production:
  adapter: mysql2
  encoding: utf8
  database: foreman
  username: foreman
  password: foreman
  host: localhost
  socket: "/var/lib/mysql/mysql.sock"
DELIM

#using the default configuraiton provided by foreman for intial setup
cp -f /usr/share/foreman/config/settings.yaml.example /etc/foreman/settings.yaml
#populate database with appropriate tables to be used by foreman
jline "Initializing foreman database migration"
( cd /usr/share/foreman &&  RAILS_ENV=production rake db:migrate )
#su - foreman -s /bin/bash -c /usr/share/foreman/extras/dbmigrate

#configure foreman to use passenger
jline "Configuring Foreman to use Passenger"
cat > /etc/httpd/conf.d/foreman.conf << DELIM
 <VirtualHost IP_PH:80>
  ServerName PUPPET_SERVER_PH
  ServerAlias foreman
  DocumentRoot /usr/share/foreman/public
  PassengerAppRoot /usr/share/foreman

  RailsAutoDetect On
  AddDefaultCharset UTF-8

</VirtualHost>

<VirtualHost IP_PH:443>
  ServerName PUPPET_SERVER_PH
  ServerAlias foreman

  RailsAutoDetect On
  DocumentRoot /usr/share/foreman/public
  PassengerAppRoot /usr/share/foreman

  # Use puppet certificates for SSL

  SSLEngine On
  SSLCertificateFile      /var/lib/puppet/ssl/certs/PUPPET_SERVER_PH.pem
  SSLCertificateKeyFile   /var/lib/puppet/ssl/private_keys/PUPPET_SERVER_PH.pem
  SSLCertificateChainFile /var/lib/puppet/ssl/certs/ca.pem
  SSLCACertificateFile    /var/lib/puppet/ssl/certs/ca.pem
  SSLVerifyClient         optional
  SSLOptions              +StdEnvVars
  SSLVerifyDepth          3

</VirtualHost>
DELIM
sed -i "s/PUPPET_SERVER_PH/${PUPPET_SERVER}/g" /etc/httpd/conf.d/foreman.conf
sed -i "s/IP_PH/${IP}/g" /etc/httpd/conf.d/foreman.conf

/etc/init.d/httpd restart

echo "Now foreman is up and running you can see the webpage @ http://${IP}"

######################################################
#Integrate Puppet and Foreman for Reporting
######################################################
if yesno "Do you want to setup foreman for puppet reporting"
then
#Foreman for reporting
jline "Building ruby script for puppet to report to foreman"
cat > /usr/lib/ruby/site_ruby/1.8/puppet/reports/foreman.rb << DELIM

# copy this file to your report dir - e.g. /usr/lib/ruby/1.8/puppet/reports/
# add this report in your puppetmaster reports - e.g, in your puppet.conf add:
# reports=log, foreman # (or any other reports you want)

#foreman reporting script that uses ssl
#http://pastebin.com/YqNWEPHN

# URL of your Foreman installation
\$foreman_url='http://FOREMAN_SERVER_PH'

require 'puppet'
require 'net/http'
require 'net/https'
require 'uri'

Puppet::Reports.register_report(:foreman) do
    Puppet.settings.use(:reporting)
    desc "Sends reports directly to Foreman"

    def process
      begin
        uri = URI.parse(\$foreman_url)
        http = Net::HTTP.new(uri.host, uri.port)
        if uri.scheme == 'https' then
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end
        req = Net::HTTP::Post.new("#{uri.path}/reports/create?format=yml")
        req.set_form_data({'report' => to_yaml})
        response = http.request(req)
      rescue Exception => e
        raise Puppet::Error, "Could not send report to Foreman at #{\$foreman_url}/reports/create?format=yml: #{e}"
      end
    end
end

DELIM

sed -i "s/FOREMAN_SERVER_PH/${PUPPET_SERVER}:3000/g" /usr/lib/ruby/site_ruby/1.8/puppet/reports/foreman.rb

#tell puppet and puppet agent to report back to foreman as well as logs
sed -i '/main/ a\    reports = log, foreman' /etc/puppet/puppet.conf
sed -i '/agent/ a\    report = true' /etc/puppet/puppet.conf

/etc/init.d/httpd restart

echo "running a sample puppet agent run so that it can report to foreman"
puppet agent --test
echo "now you can see the puppet agent report in the foreman web-page"
fi

##########################################################
#Integrate Puppet with Foreman as External Node Classifier
##########################################################
if yesno "Do you want foreman as ENC "
then
#import existing puppet classes and modules into foreman from cli
# or from web ui -> Simply goto either Environments or Classes page (under more) and click import.
jline "IMporintg puppet Environments to foreman"
( cd /usr/share/foreman && rake puppet:import:puppet_classes[batch] RAILS_ENV=production )

jline "Building ruby script for puppet ENC"
cat > /etc/puppet/node.rb << DELIM
#! /usr/bin/env ruby

SETTINGS = {
  :url          => "http://PUPPET_SERVER_PH",
  :puppetdir    => "/var/lib/puppet",
  :facts        => true,
  :storeconfigs => true,
  :timeout      => 3,
}

### Do not edit below this line

def url
  SETTINGS[:url] || raise("Must provide URL - please edit file")
end

def certname
  ARGV[0] || raise("Must provide certname as an argument")
end

def puppetdir
  SETTINGS[:puppetdir] || raise("Must provide puppet base directory - please edit file")
end

def stat_file
  FileUtils.mkdir_p "#{puppetdir}/yaml/foreman/"
  "#{puppetdir}/yaml/foreman/#{certname}.yaml"
end

def tsecs
  SETTINGS[:timeout] || 3
end

require 'net/http'
require 'net/https'
require 'fileutils'
require 'timeout'

def upload_facts
  # Temp file keeping the last run time
  last_run = File.exists?(stat_file) ? File.stat(stat_file).mtime.utc : Time.now - 365*24*60*60
  filename = "#{puppetdir}/yaml/facts/#{certname}.yaml"
  last_fact = File.stat(filename).mtime.utc
  if last_fact > last_run
    fact = File.read(filename)
    begin
      uri = URI.parse("#{url}/fact_values/create?format=yml")
      req = Net::HTTP::Post.new(uri.path)
      req.set_form_data('facts' => fact)
      res             = Net::HTTP.new(uri.host, uri.port)
      res.use_ssl     = uri.scheme == 'https'
      res.verify_mode = OpenSSL::SSL::VERIFY_NONE if res.use_ssl
      res.start { |http| http.request(req) }
    rescue => e
      raise "Could not send facts to Foreman: #{e}"
    end
  end
end

def cache result
  File.open(stat_file, 'w') {|f| f.write(result) }
end

def read_cache
  File.read(stat_file)
rescue => e
  raise "Unable to read from Cache file: #{e}"
end

def enc
  foreman_url      = "#{url}/node/#{certname}?format=yml"
  uri              = URI.parse(foreman_url)
  req              = Net::HTTP::Get.new(foreman_url)
  http             = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl     = uri.scheme == 'https'
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE if http.use_ssl
  res              = http.start { |http| http.request(req) }

  raise "Error retrieving node #{certname}: #{res.class}" unless res.code == "200"
  res.body
end

# Actual code starts here
begin
  # send facts to Foreman - optional uncomment 'upload_facts' to activate.
  # if you use this option below, make sure that you don't send facts to foreman via the rake task or push facts alternatives.
  #
  if ( SETTINGS[:facts] ) and not ( SETTINGS[:storeconfig] )
    upload_facts
  end
  #
  # query External node
  begin
    result = ""
    timeout(tsecs) do
      result = enc
      cache result
    end
  rescue TimeoutError, SocketError, Errno::EHOSTUNREACH
    # Read from cache, we got some sort of an error.
    result = read_cache
  ensure
    puts result
  end
rescue => e
  warn e
  exit 1
end
DELIM

sed -i "s/FOREMAN_SERVER_PH/${PUPPET_SERVER}:3000/g" /etc/puppet/node.rb
chown puppet /etc/puppet/node.rb
chmod +x /etc/puppet/node.rb

#tell puppet to use external nodes
sed -i '/master/ a\    external_nodes = /etc/puppet/node.rb' /etc/puppet/puppet.conf
sed -i '/external_nodes/ a\    node_terminus  = exec' /etc/puppet/puppet.conf

/etc/init.d/httpd restart

echo "Foreman is now ENC for puppet,
please verify by going into foreman console and click on YAML link for any client node"
fi

#############################################
#Foreman Smart-Proxy - for host provisioning
#############################################
if yesno "Do you want to setup foreman-proxy for host provisioning "
then
  #####################################################
  #configure smart-proxy to control puppet-certificates
  #####################################################
  #allow foreman-proxy user to run puppet commands - settings.yml
  jline "Adding Foreman users to sudoers file"
echo "Defaults:foreman !requiretty
Defaults:foreman-proxy !requiretty
foreman ALL=(ALL) NOPASSWD:/usr/sbin/puppetrun
foreman-proxy ALL=(ALL) NOPASSWD:/usr/bin/puppet
foreman-proxy ALL=(ALL) NOPASSWD:/usr/sbin/puppetrun
foreman-proxy ALL=(ALL) NOPASSWD:/usr/sbin/puppetca*" >> /etc/sudoers

chmod 0440 /etc/sudoers

jline 'Building foreman-proxy settings file'
cat > /etc/foreman-proxy/settings.yml << DELIM
---
:daemon: true
:daemon_pid: /var/run/foreman-proxy/foreman-proxy.pid
:port: 8443
:tftp: false
:dns: false
:dhcp: false
:dhcp_vendor: isc
:puppetca: true
:puppet: true
:puppet_conf: /etc/puppet/puppet.conf
:log_file: /var/log/foreman-proxy/proxy.log
DELIM

  #permissions
  usermod -G puppet foreman-proxy
  chown -R puppet:puppet /etc/puppet
  chmod 664 /etc/puppet/*.conf

  #restart proxy
  /etc/init.d/foreman-proxy restart

  echo "Now the foreman-proxy is running, available features list is @
  http://${IP}:8443/features"

  ########################################
  #configure TFTP
  ########################################
  echo "Installing tftp packages"
  yum install -y tftp-server syslinux xinetd
  mkdir /tftpboot
  chown -R foreman-proxy:puppet /tftpboot/
  chmod 775 /tftpboot
  cp /usr/share/syslinux/pxelinux.0 /tftpboot
  sed -i "s/:tftp: false/:tftp: true/g" /etc/foreman-proxy/settings.yml
  sed -i '/:tftp: true/ a\:tftproot: /tftpboot' /etc/foreman-proxy/settings.yml
  # sed -i "s/        server_args             = -s \/var\/lib\/tftpboot/        server_args             = -s \/tftpboot/g" /etc/xinetd.d/tftp
  # sed -i "s/        disable                 = yes/        disable                 = no/g" /etc/xinetd.d/tftp
  jline "Building tftp configuraiton"
cat > /etc/xinetd.d/tftp << DELIM
service tftp
{
  socket_type   = dgram
  protocol    = udp
  wait      = yes
  user      = root
  server      = /usr/sbin/in.tftpd
  server_args   = -s TFTP_PATH_PH
  disable     = no
  per_source    = 11
  cps     = 100 2
  flags     = IPv4
}
DELIM
  sed -i "s/TFTP_PATH_PH/\/tftpboot/g" /etc/xinetd.d/tftp
  mkdir -p /tftpboot/boot
  jline "Downloading centos image files vmlinuz and initrd.img"
  ( cd /tftpboot && wget http://mirrors.kernel.org/centos/6/os/x86_64/images/pxeboot/initrd.img )
  ( cd /tftpboot && wget http://mirrors.kernel.org/centos/6/os/x86_64/images/pxeboot/vmlinuz )
  chown -R foreman-proxy:root /tftpboot
  /etc/init.d/xinetd restart
  /etc/init.d/foreman-proxy restart

  echo "Now, you can see TFTP enabled @ http://${IP}:8443/features"

  ########################################
  #configure DHCP
  ########################################
  echo "Installing dhcp packages"
  yum install -y libffi libffi-devel dhcp bind bind-utils bind-chroot bind-libs
  #Generate shared key for DHCP management via OMAPI protocol
  cd /tmp
  dnssec-keygen -r /dev/urandom -a HMAC-MD5 -b 512 -n HOST omapi_key
  DHCP_KEY=`cat Komapi_key.+*.private |grep ^Key|cut -d ' ' -f2-`
  jline 'Building dhcpd config'
echo "omapi-port 7911;
  key omapi_key {
    algorithm HMAC-MD5;
    secret \"${DHCP_KEY}\";
  };
  omapi-key omapi_key;

  allow booting;
  allow bootp;

  subnet 192.168.1.0 netmask 255.255.255.0 {
      range 192.168.1.100 192.168.1.200;
      option domain-name-servers 8.8.8.8;
      option domain-name ${DOMAIN_NAME};
      option routers 192.168.1.1;
      filename \"/tftpboot/pxelinux.0\";
      allow booting;
      allow bootp;
      next-server $IP;
  }" /etc/dhcpd.conf


sed -i "s/:dhcp: false/:dhcp: true/g" /etc/foreman-proxy/settings.yml
echo ":dhcp_config: /etc/dhcpd.conf
:dhcp_leases: /var/lib/dhcpd/dhcpd.leases
:dhcp_key_name: omapi_key
:dhcp_key_secret: $DHCP_KEY" >> /etc/foreman-proxy/settings.yml

  ( cd /tmp && rm -rf *.key )
  ( cd /tmp && rm -rf *.private )

chown root:puppet /etc/dhcpd.conf
chown dhcpd:puppet /var/lib/dhcpd/dhcpd.leases
chmod 664 /var/lib/dhcpd/dhcpd.leases
rm -rf /etc/dhcp/dhcpd.conf
ln -s /etc/dhcpd.conf /etc/dhcp/dhcpd.conf

/etc/init.d/dhcpd restart
/etc/init.d/foreman-proxy restart

echo "Now, you can see DCHP enabled @ http://${IP}:8443/features"

  ########################################
  #configure DNS
  ########################################
  sed -i "s/ROOTDIR=\/var\/named\/chroot/#ROOTDIR=\/var\/named\/chroot/g" /etc/sysconfig/named
  #create shared keys
  ( cd /var/named/chroot/etc && dnssec-keygen -a HMAC-MD5 -b 128 -n HOST foreman )
  DNS_KEY=`cat *.key | awk '{ print $NF }'`
  echo "key \"foreman\" {
          algorithm hmac-md5;
          secret \"${DNS_KEY}\";
  };" > /var/named/chroot/etc/foreman.key


  #generate rndc-key
  RNDC_KEY_TMP=`rndc-confgen -r /dev/urandom -b 256 | grep secret | grep -o '"[^"]*"' | head -1`
  RNDC_KEY=`echo ${RNDC_KEY_TMP} | awk -F\" '{print $(NF-1)}'`
jline "Building named config"
echo "key \"rndc-key\" {
  algorithm hmac-md5;
  secret \"${RNDC_KEY}\";
};

options {
  default-key \"rndc-key\";
  default-server 127.0.0.1;
  default-port 953;
};" > /var/named/chroot/etc/rndc.key

rm -rf /etc/rndc.key
ln -s /var/named/chroot/etc/rndc.key /etc/rndc.key

echo "key \"rndc-key\" {
  algorithm hmac-md5;
  secret \"${RNDC_KEY}\";
};

key \"foreman\" {
          algorithm hmac-md5;
          secret \"${DNS_KEY_PH}\";
  };

controls {
  inet ${IP} port 953
  allow { ${IP}; } keys { \"rndc-key\"; };
};

controls {
  inet 127.0.0.1 port 953
  allow { 127.0.0.1; } keys { \"rndc-key\"; };
};
options {
  directory \"/var/named\";
  forwarders {8.8.8.8; };
};
zone \".\" IN {
  type hint;
  file \"named.ca\";
};

zone \"${DOMAIN_NAME}\" IN {
        type master;
        file \"/var/named/${DOMAIN_NAME}.fwd\";
        allow-update { key \"rndc-key\"; key \"foreman\"; };
};

zone \"1.168.192.in-addr.arpa\" IN {
        type master;
        file \"/var/named/${DOMAIN_NAME}.rev\";
        allow-update { key \"rndc-key\"; key \"foreman\"; };
};
include \"/etc/named.rfc1912.zones\";" > /var/named/chroot/etc/named.conf

jline "Building DNS Zone files"
cat > /var/named/${DOMAIN_NAME}.fwd << DELIM
\$TTL 86400
@ IN SOA PUPPET_SERVER_PH. hostmaster.DOMAIN_PH. (
2012092501	; serial
21600	; refresh every 6 hours
3600	; retry after one hour
604800	; expire after a week
86400 )	; minimum TTL of 1 day

@ IN NS PUPPET_SERVER_PH.
@ IN MX 10 PUPPET_SERVER_PH.
mailer IN A IP_PH
HOSTNAME_PH IN A IP_PH
PUPPET_SERVER_PH. IN A IP_PH
DELIM

  sed -i "s/PUPPET_SERVER_PH/${PUPPET_SERVER}/g" /var/named/${DOMAIN_NAME}.fwd
  sed -i "s/DOMAIN_PH/${DOMAIN_NAME}/g" /var/named/${DOMAIN_NAME}.fwd
  sed -i "s/HOSTNAME_PH/${HOSTNAME}/g" /var/named/${DOMAIN_NAME}.fwd
  sed -i "s/IP_PH/${IP}/g" /var/named/${DOMAIN_NAME}.fwd

  echo "checking for errors in the dns configuraiton"
  named-checkzone ${DOMAIN_NAME} /var/named/${DOMAIN_NAME}.fwd

cat > /var/named/${DOMAIN_NAME}.rev << DELIM
\$TTL 86400
@ IN SOA PUPPET_SERVER_PH. hostmaster.DOMAIN_PH. (
2012092502 ; serial
21600 ; refresh after 6 hours
3600 ; retry in 1 hour
604800 ; expire after a week
86400 ) ; minimum TTL of one day

@ IN NS PUPPET_SERVER_PH.

IP_LAST_OCTECT_PH IN PTR PUPPET_SERVER_PH.
;3  IN  PTR switch.debiantest.net.
;1  IN  PTR mailer.debiantest.net.
;20 IN PTR relay.debiantest.net.
DELIM

  sed -i "s/DOMAIN_PH/${DOMAIN_NAME}/g" /var/named/${DOMAIN_NAME}.rev
  sed -i "s/PUPPET_SERVER_PH/${PUPPET_SERVER}/g" /var/named/${DOMAIN_NAME}.rev
  sed -i "s/IP_LAST_OCTECT_PH/${IP_LAST_OCTECT}/g" /var/named/${DOMAIN_NAME}.rev

  echo "checking for errors in the dns configuraiton"
  named-checkzone 1.168.192.in-addr.arpa /var/named/${DOMAIN_NAME}.rev

  sed -i "s/:dns: false/:dns: true/g" /etc/foreman-proxy/settings.yml

  usermod -G named foreman-proxy
  chown -R named:named /var/named/
  chown foreman-proxy /var/named/chroot/etc/*.key
  chown foreman-proxy /var/named/chroot/etc/*.private
  ( cd /var/named && find . -type f -exec chmod 664 {} \; )
  chmod 400 /var/named/chroot/etc/*.private

  PRIVATE_KEY_FILE=`ls /var/named/chroot/etc/ | grep *.private`
  echo ":dns_key: /var/named/chroot/etc/${PRIVATE_KEY_FILE}" >> /etc/foreman-proxy/settings.yml

  #move the existing named.conf file
  mv /etc/named.conf /etc/named.conf.back
  ln -s /var/named/chroot/etc/named.conf /etc/named.conf
  #rebuild /etc/resolve.conf file to accomadate new nameserver
  echo "nameserver $IP" > /etc/resolv.conf

  /etc/init.d/named restart
  /etc/init.d/foreman-proxy restart
  /etc/init.d/httpd restart

  echo "Now, you can see DNS enabled @ http://${PUPPET_SERVER}:8443/features"

else
  echo "Not installing foreman-proxy"
fi

#######################
#Foreman CRON JOBS
#######################
#expire reports handling, cron job for running every day @ 00:30
#expires all reports regardless of their status
echo "30 00 * * * cd /usr/share/foreman && /usr/bin/rake reports:expire days=7 RAILS_ENV=\"production\" >/dev/null 2>> /var/log/foreman/cron.log" > /root/cronjobsforeman
#import the facts into foreman, if puppetmaster and foreman are on the same machine
echo "*/30 * * * * cd /usr/share/foreman && rake puppet:import:hosts_and_facts RAILS_ENV=\"production\" >/dev/null 2>> /var/log/foreman/cron.log" > /root/cronjobsforeman
#enable this cron job only after setting email settings for foreman
#echo "# sends out a summary email for the last 24 hours
#0 23 * * * cd /usr/share/foreman/ && rake reports:summarize hours=24 RAILS_ENV=\"production\" >/dev/null 2>> /var/log/foreman/cron.log" > /root/cronjobsforeman
#puppet agent run cron job
echo "sleep \$((RANDOM%59)) && /usr/sbin/puppet agent --config /etc/puppet/puppet.conf --onetime --no-daemonize >/dev/null 2>> /var/log/foreman/cron.log" > /root/cronjobsforeman
#load the cron jobs
crontab /root/cronjobsforeman


#######################
#MCOLLECTIVE
#######################
if yesno "Do you want to setup mcollective"
then
  #install required packages
  yum -y install erlang rabbitmq-server
  #install stomp plugins
  jline "Installing Stomp Plugins"
  cd /usr/lib/rabbitmq/lib/rabbitmq_server-2.6.1/plugins
  wget http://www.rabbitmq.com/releases/plugins/v2.6.1/amqp_client-2.6.1.ez
  wget http://www.rabbitmq.com/releases/plugins/v2.6.1/rabbitmq_stomp-2.6.1.ez
  chmod 644 *.ez
  /etc/init.d/rabbitmq-server start

  #configuring rabbit-mq stomp listener
  jline "Configuring rabbitmq stomp listener"
  puppet resource file /etc/rabbitmq/rabbitmq.config content='[ {rabbit_stomp, [{tcp_listeners, [6163]} ]} ].'
  #use this instead anc check
  #echo "SERVER_START_ARGS=\"-rabbit_stomp listeners [{\"0.0.0.0\",6163}]\"" > /etc/rabbitmq/rabbitmq.conf
  #restart rabbitmq and verify stomp tcp port
  /etc/init.d/rabbitmq-server restart
  STOMP_PORT="61613"  #default port
  netstat -nlp | grep 6163
  if [ $? -eq 0 ]
  then
    echo "stomp is listening on tcp port 6163"
    STOMP_PORT="6163"
  else
    echo "stomp is not listening on 6163 please check the port 61613"
    netstat -nlp | grep 61613
    if [ $? -eq 0 ]
    then
      echo "stomp is listening on tcp port 61613"
      STOMP_PORT="61613"
    else
      echo "stomp is not listening on any port please check logs, aborting"
    fi
  fi
  jline "Configuring rabbitmq users"
  read -s -p "Enter the mcollective user password:" MCOLLECTIVE_USER_PASSWD
  #configuring rabbitmq mcollective account
  rabbitmqctl add_user mcollective $MCOLLECTIVE_USER_PASSWD
  #permissions are granted to allow MCollective client and server processes to exchange messages
  rabbitmqctl set_permissions -p / mcollective "^amq.gen-.*" ".*" ".*"
  #delete the guest account
  rabbitmqctl delete_user guest

  #install mcollective
  #Install mcollective-client on the server box ONLY. This is the box from where you'll control the mcollective activities.
  yum -y install mcollective mcollective-common mcollective-client
  gem install stomp
  STOMP_HOST=`uname -n`
  ###########
  #Change /etc/mcollective/server.cfg (client nodes)
  #and /etc/mcollective/client.cfg (node you will be running requests from)
  ###########

#mcollective server configuration
jline "Building mcollective-server config"
cat > /etc/mcollective/server.cfg << DELIM
topicprefix = /topic/mcollective
libdir = /usr/share/mcollective/plugins
logfile = /var/log/mcollective.log
loglevel = info
daemonize = 1
# Plugins
securityprovider = psk
plugin.psk = klot2oj2ked2tayn3hu5on7l
connector = stomp
plugin.stomp.host = STOMP_HOST_PH
plugin.stomp.port = STOMP_PORT_PH
plugin.stomp.user = mcollective
plugin.stomp.password = MCOLLECTIVE_USER_PASSWD_PH
# Facts
factsource = yaml
plugin.yaml = /etc/mcollective/facts.yaml

DELIM
  #user can change plusgin.psk to a random generated string and should be same accross cluster
  sed -i "s/STOMP_PORT_PH/STOMP_PORT/g" /etc/mcollective/server.cfg
  sed -i "s/STOMP_HOST_PH/STOMP_HOST/g" /etc/mcollective/server.cfg
  sed -i "s/MCOLLECTIVE_USER_PASSWD_PH/MCOLLECTIVE_USER_PASSWD/g" /etc/mcollective/server.cfg

  #restart mcollective server
  /etc/init.d/mcollective restart

#mcollective client configuration
jline "Building mcollective-client config"
cat > /etc/mcollective/client.cfg << DELIM
topicprefix = /topic/mcollective
libdir = /usr/share/mcollective/plugins
logfile = /dev/null
loglevel = info
# Plugins
securityprovider = psk
plugin.psk = klot2oj2ked2tayn3hu5on7l
connector = stomp
plugin.stomp.host = STOMP_HOST_PH
plugin.stomp.port = STOMP_PORT_PH
plugin.stomp.user = mcollective
plugin.stomp.password = MCOLLECTIVE_USER_PASSWD_PH
# Facts
factsource = yaml
plugin.yaml = /etc/mcollective/facts.yaml
DELIM

  sed -i "s/STOMP_PORT_PH/STOMP_PORT/g" /etc/mcollective/client.cfg
  sed -i "s/STOMP_HOST_PH/STOMP_HOST/g" /etc/mcollective/client.cfg
  sed -i "s/MCOLLECTIVE_USER_PASSWD_PH/MCOLLECTIVE_USER_PASSWD/g" /etc/mcollective/client.cfg

  #test communication betwen mcollective server process
  mco ping
  if [ $? -eq 0 ]
  then
    echo "MCollective server is running and responding to messages"
  else
    echo "MCollective server is not running and not responding to messages, check log /var/log/rabbitmq for more info."
  fi

  #mcollective agent plugins
  #more plugins available @ https://github.com/puppetlabs/mcollective-plugins
  jline "Downloading mcollective plugins"
  cd ~
  git clone git://github.com/puppetlabs/mcollective-plugins.git
  #send mcollective agent plugins to all agents
  cd /usr/libexec/mcollective/mcollective/application
  for i in filemgr nettest package puppetd service; do
  wget https://raw.github.com/puppetlabs/mcollective-plugins/master/agent/$i/application/$i.rb
  done
  wget https://raw.github.com/phobos182/mcollective-plugins/master/agent/etcfacts/application/etcfacts.rb
  wget https://raw.github.com/phobos182/mcollective-plugins/master/agent/shellcmd/application/shellcmd.rb
  wget https://raw.github.com/phobos182/mcollective-plugins/master/agent/yum/application/yum.rb

  cd /usr/libexec/mcollective/mcollective/agent
  for i in nettest filemgr puppetd puppetral puppetca; do
  wget https://raw.github.com/puppetlabs/mcollective-plugins/master/agent/$i/agent/$i.rb
  wget https://raw.github.com/puppetlabs/mcollective-plugins/master/agent/$i/agent/$i.ddl
  done

  wget -O package.rb https://raw.github.com/puppetlabs/mcollective-plugins/master/agent/package/agent/puppet-package.rb
  wget https://raw.github.com/puppetlabs/mcollective-plugins/master/agent/package/agent/package.ddl
  wget -O service.rb https://raw.github.com/puppetlabs/mcollective-plugins/master/agent/service/agent/puppet-service.rb
  wget https://raw.github.com/puppetlabs/mcollective-plugins/master/agent/service/agent/service.ddl
  wget https://raw.github.com/phobos182/mcollective-plugins/master/agent/etcfacts/etc_facts.rb
  wget https://raw.github.com/phobos182/mcollective-plugins/master/agent/etcfacts/etc_facts.ddl
  wget https://raw.github.com/phobos182/mcollective-plugins/master/agent/shellcmd/shellcmd.rb
  wget https://raw.github.com/phobos182/mcollective-plugins/master/agent/shellcmd/shellcmd.ddl
  wget https://raw.github.com/phobos182/mcollective-plugins/master/agent/yum/yum.rb
  wget https://raw.github.com/phobos182/mcollective-plugins/master/agent/yum/yum.ddl

  cd /usr/libexec/mcollective/mcollective/facts/
  wget https://raw.github.com/puppetlabs/mcollective-plugins/master/facts/facter/facter_facts.rb

  #load the puppet agent plugin
  /etc/init.d/mcollective restart
  chkconfig mcollective on
  #test puppet run
  jline "test puppet run using mcollective"
  mco rpc puppetd runonce -v
  #run on specigied agent
    #mco rpc puppetd runonce -l <client_name> -v


fi


cat << INSTRUCTIONS

Next Steps:
----------

1. Add a Smart Proxy in Foreman.

  Form the dropdown menu:

  (i)Select "Smart Proxies", "New Proxy"
  (ii)Enter its name and the URL with port(http://${IP}:8443).
  (iii)Then click on "Submit".

2. Now you need to tell Foreman he can manage a new DNS domain.

  From the dropdown menu:

  (i)Select "Domains" then "New Domain"
  (ii)Enter a name and the domain name
  (iii)Associate it to your Smart Proxy
  (iv)Save

3. To add a subnet in Foreman:

  From the dropdown menu:

  (i)Select "Subnets"
  (ii)Click on "New Subnet"
  (iii)Enter a name, the associated domain, the network informations
  and the Smart Proxy server that you want to associate with this subnet
  (iv)And save

4. Add Installation Media

5. Add Operating System

6. Add Provisioning Templates and associate it with Operating System (or) Host Groups

4. In order to get full automation of tftp configuration you would need:

  (i)Add that smart proxy under settings --> smart proxies (refer step 1)
  (ii)Create a domain where you would like to deploy your host on (refer step 2)
  (iii)Create a subnet, and select the relevant domain and smart proxy in it. (refer step 3)
  (iv)Create a host, select the domain / subnet etc


INSTRUCTIONS

fi



#puppet client setup
if [ "$PC_SETUP" == "1" ]
then
STOMP_HOST=`uname -n`
STOMP_PORT="61613"
echo "Installing puppet client in "
yum -y install puppet mcollective-common mcollective-client
read -p "Enter the fqdn of puppet server: " $PUPPET_SERVER_CLIENT

cat > /etc/puppet/puppet.conf << DELIM
[main]
  reports = foreman
  logdir = /var/log/puppet
  rundir = /var/run/puppet
  ssldir = $vardir/ssl
  server = PUPPET_SERVER_PH

[agent]
  report = true
  classdir = $vardir/classes.txt
  localconfig = $vardir/localconfig

DELIM

sed -i "s/PUPPET_SERVER_PH/${PUPPET_SERVER_CLIENT}/g" /etc/puppet/puppet.conf

echo "installing mcollective on client"
yum install -y mcollective-common mcollective
gem install stomp
#Change /etc/mcollective/server.cfg (client nodes)
#and /etc/mcollective/client.cfg (node you will be running requests from)
cat > /etc/mcollective/server.cfg << DELIM
topicprefix = /topic/mcollective
libdir = /usr/share/mcollective/plugins
logfile = /var/log/mcollective.log
loglevel = info
daemonize = 1
# Plugins
securityprovider = psk
plugin.psk = klot2oj2ked2tayn3hu5on7l
connector = stomp
plugin.stomp.host = STOMP_HOST_PH
plugin.stomp.port = STOMP_PORT_PH
plugin.stomp.user = mcollective
plugin.stomp.password = mcollective
# Facts
factsource = yaml
plugin.yaml = /etc/mcollective/facts.yaml

DELIM
#user can change plusgin.psk to a random generated string and should be same accross cluster
sed -i "s/STOMP_PORT_PH/STOMP_PORT/g" /etc/mcollective/server.cfg
sed -i "s/STOMP_HOST_PH/STOMP_HOST/g" /etc/mcollective/server.cfg

/etc/init.d/mcollective restart

fi

exit 0