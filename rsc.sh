#!/usr/bin/env bash
####################
#
# Wrapper script to manage virtual machines in rackspace using nova-client & rackspace api v2
# Replcae the variables values below to point to correct account
# Author: Ashrith
#
####################

##NOVA AUTH VARIABLES
export OS_AUTH_URL=https://identity.api.rackspacecloud.com/v2.0/
export OS_AUTH_SYSTEM=rackspace
export OS_REGION_NAME=DFW
export OS_USERNAME=<username> #username for rackspace
export OS_TENANT_NAME=<account_num> #account number
export NOVA_RAX_AUTH=1
export OS_PASSWORD=<api_key> #api_key
export OS_PROJECT_ID=<account_num> #account number
export OS_NO_CACHE=1

function usage () {
script=$0
cat << USAGE
Manage Virtual Machines in Rackspace environment
Syntax
`basename $script` -i -l -f -C {hostname} -U {hostname} -M {REGEX} -D {hostname|id} -S {id} -P {passwd}

-i: list available images
-l: list all running virtual machines
-f: list all flavors
-C: create new centos virutual machine
-U: create new ubuntu virtual machine
-M: create multiple servers based on user input
-D: destroy a existing virtual machine
-S: show status of vm
-P: change root password
-h: show help
USAGE
exit 1
}

#check if nova client is installed or not
function check_nova () {
type -P nova &> /dev/null || ( echo "nova client is not installed."
    echo "Follow this link to install and configure nova client"
    echo "http://docs.rackspace.com/servers/api/v2/cs-gettingstarted/content/overview.html"
    exit )
}

function auth_nova () {
    #Verify if the auth is sucessful
    check_nova
    nova credentials &> /dev/null && echo "Successfully authenticated with Rackspace" || ( echo "Problem authenticating with Rackspace, please check the global variables in the script"; exit 1 )
}

function create_single_centos () {
    #create centos server
    auth_nova
    if [ $? -eq 0 ]; then
        echo "Creating CentOS 6.3 VM with 2GB MEM and 80GB Storage, this may take some time"
        nova boot ${SERVERNAME} --image "c195ef3b-9195-4474-b6f7-16e5bd86acd0" --flavor 4
        [ $? -eq 0 ] && echo "Note the ID from above output to check the vm status using `basename $0` -S <id>"
    fi
}

function create_single_ubuntu () {
    auth_nova
    if [ $? -eq 0 ]; then
        echo "Creating Ubuntu 12.04 VM with 2GB MEM and 80GB Storage, this may take some time"
        nova boot ${SERVERNAME} --image "5cebb13a-f783-4f8c-8058-c4182c724ccd" --flavor 4
        [ $? -eq 0 ] && echo "Note the ID from above output to check the vm status using `basename $0` -S <id>"
    fi
}

function create_multiple_vms () {
    #evaluate regular expression
    echo "Building Multiple VMs"
    read -p "Enter the type of operating system to build (CentOS|Ubuntu): " ostype
    case $ostype in
        centos|Centos|CentOS|CENTOS)
            imguuid="c195ef3b-9195-4474-b6f7-16e5bd86acd0";;
        ubuntu|Ubuntu|UBUNTU)
            imguuid="5cebb13a-f783-4f8c-8058-c4182c724ccd";;
    esac
    read -p "Flavor type (2-512M, 3-1GB, 4-2GB, 5-4GB, 6-8GB, 7-15GB, 8-30G) : " flavor
    value=`echo "$REGEX"|sed 's:(:{:g; s:):}:g; s:|:,:g; s/^//;s/$//'`
    value=`echo "$value"|sed 's:\[:{:g; s:\]:}:g; s:-:\.\.:g; s/^//;s/$//'`
    for server in $(eval echo $value); do
        echo "Building VM $server"
        nova boot ${server} --image ${imguuid} --flavor ${flavor}
        [ $? -eq 0 ] && echo "Note the ID from above output to check the vm status using `basename $0` -S <id>, also root pwd can be changed using `basename $0` -P <hn/id>"
    done
}

function delete_vm () {
    auth_nova
    if [ $? -eq 0 ]; then
        nova list | grep ${SERVERNAME} &> /dev/null
        if [ $? -eq 0 ]; then
            echo "Deleting ${SERVERNAME}"
            nova delete ${SERVERNAME}
        else
            echo "Cannot find instance ${SERVERNAME}"
        fi
    fi
}

#Parse options
[ $# -eq 0 ] && usage
while getopts C:U:D:M:S:P:ilfh opts
do
    case $opts in
        i)
            auth_nova && nova image-list
            ;;
        l)
            auth_nova && nova list
            ;;
        f)
            auth_nova && nova flavor-list
            ;;
        C)
            #create centos server
            SERVERNAME=${OPTARG}
            create_single_centos
            ;;
        U)
            #create ubuntu server
            SERVERNAME=${OPTARG}
            create_single_ubuntu
            ;;
        M)
            #create multiple servers
            REGEX=${OPTARG}
            create_multiple_vms
            ;;
        D)
            #delete existing vm
            SERVERNAME=${OPTARG}
            delete_vm
            ;;
        S)
            #check status of the vm using vm id
            auth_nova && nova show ${OPTARG}
            ;;
        P)
            #change root password of server
            auth_nova && nova root-password ${OPTARG}
            ;;
        h)
            usage
            ;;
        \?)
            usage
            ;;
    esac
done