scripts
=======

###aws-cmdline 

command line client application to amazon's elastic compute cloud (ec2).

`Features:`

Allows user to

- create/list/delete instances (virtual machines)
- create/associate/disassociate/release elastic ips to instances
- create/list/delete spot requests
- start/stop/reboot/terminate instnaces
- view spot request price history
- S3 interface to create/list/delete buckets
  - upload files to buckets
  - download file from buckets
  - list bucket contents

`Usage: ./aws-cmdline help`

Tested and working in Ruby 1.8 & 1.9

###rsc

command line client application for rackspace's openstack cloud

`Features:`

Allows user to

- create/list/destroy virtual machines
- list available images/instance flavors
- change root password for specified isntance
- multi mode, where user can create multiple isnstances at a time

`Usage: ./rsc -h`

###puppet-installer

Script to install puppet server/agent

`Features:`

Allows user to install:

- puppet server
- puppetdb for stored configuraitons
- postgresql for backing puppetdb (dependecy)
- fusion passenger to scale puppet server
- puppet agent

`Usage: ./puppetinstaller -h`

Tested and working in CentOS 6.2/Ubuntu 12.04


###random-generator

experimental ruby program to generate radom data which can be used for analytics purposes.

`Usage: ./random_generator`


###foreman1.0

Script to install foreman and all its dependencies.