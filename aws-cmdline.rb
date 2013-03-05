#!/usr/bin/env ruby
#
# ===
# => AWS EC2 Command Line Interface
# => Author: Ashrith
# ===

%w(rubygems thor aws-sdk terminal-table yaml rainbow net/http net/ssh logger json open-uri).each { |g| require g }

CONFIG_FILE = File.join(File.dirname(__FILE__), "config.yml")

def create_connection
  # => returns a AWS connection object
  error_msg = "Config file should be present @ #{CONFIG_FILE} and contents should contain:\n"\
    "access_key_id: YOUR_ACCESS_KEY_ID\n"\
    "secret_access_key: YOUR_SECRET_ACCESS_KEY\n"
  unless File.exist?(CONFIG_FILE)
    print "Missing Config file\n".color :red
    print error_msg
    exit 1
  end
  #parse config file
  @config = YAML.load(File.read(CONFIG_FILE))
  unless @config.kind_of?(Hash)
    print "Parse Error\n".color :red
    print error_msg
    exit 1
  end
  #enable logging
  @config.merge!(:logger => Logger.new($stdout))

  AWS.config(@config)
  AWS::EC2.new
end # => create_connection

class ElasticIp < Thor
  desc "list", "lists available elastic ip(s)"
  option :region,
         aliases: "-r",
         desc: "region to used if specified"
  def list
    ec2 = create_connection
    if options[:region]
      abort "invalid region name: #{options[:region]}" unless ec2.regions.map(&:name).include?(options[:region].to_s)
      ec2 = ec2.regions[options[:region]]
    end
    elasticips = ec2.elastic_ips.inject([]) do |m, i|
      (n ||= []) << i.public_ip << i.domain << i.instance_id
      m << n
      m
    end
    table = Terminal::Table.new :headings => ['PublicIP', 'Domain', 'Associated Instance ID'], :rows => elasticips
    elasticips.empty? ? puts("No Elastic IPs found".color :yellow) : puts(table)
  end

  desc "new", "request a new elastic ip"
  option :region,
         aliases: "-r",
         desc: "region to used if specified"
  option :num_of_ips,
         type: :numeric,
         aliases: "-n",
         default: 1,
         desc: "number of elastic ips to create"
  def new
    ec2 = create_connection
    if options[:region]
      abort "invalid region name: #{options[:region]}" unless ec2.regions.map(&:name).include?(options[:region].to_s)
      ec2 = ec2.regions[options[:region]]
    end
    (1..options[:num_of_ips]).each do
      eip = ec2.elastic_ips.create
      puts "Elastic IP created: #{eip.public_ip}".color :green
    end
  end

  desc "associate", "associate an elastic ip to instance"
  option :region,
         aliases: "-r",
         desc: "region to used if specified"
  option :instance_id,
         aliases: "-i",
         required: true,
         desc: "instance id to associate elastic ip to"
  option :eip,
         aliases: "-e",
         required: true,
         desc: "eip to associate"
  def associate
    ec2 = create_connection
    if options[:region]
      abort "invalid region name: #{options[:region]}" unless ec2.regions.map(&:name).include?(options[:region].to_s)
      ec2 = ec2.regions[options[:region]]
    end
    if valid_ipv4?(options[:eip])
      instance = ec2.instances[options[:instance_id]]
      abort "EIP not found".color :red unless ec2.elastic_ips.map(&:public_ip).include?(options[:eip].to_s)
      abort "Instance not found".color :red unless instance.exists?
      eip = ec2.elastic_ips[options[:eip]]
      if eip.associated?
        abort "EIP #{options[:eip]} already associated to #{eip.instance.id}".color :yellow
      else
        eip.associate :instance => instance
        puts "Associate EIP: #{options[:eip]} to instance: #{options[:instance_id]}".color :green
      end
    else
      abort "Invalid IP format".color :red
    end
  end

  desc "disassociate", "deassociate an elastic ip from instance"
  option :region,
         aliases: "-r",
         desc: "region to used if specified"
  option :eip,
         aliases: "-e",
         required: true,
         desc: "instance id to associate elastic ip to"
  def disassociate
    ec2 = create_connection
    if options[:region]
      abort "invalid region name: #{options[:region]}" unless ec2.regions.map(&:name).include?(options[:region].to_s)
      ec2 = ec2.regions[options[:region]]
    end
    if valid_ipv4?(options[:eip])
      abort "Elastic IP not found".color :red unless ec2.elastic_ips.map(&:public_ip).include?(options[:eip].to_s)
      eip = ec2.elastic_ips[options[:eip]]
      if eip.associated?
        instanceid = eip.instance.id
        eip.disassociate
        puts "EIP: #{options[:eip]} disassociated from #{instanceid}".color :green
      else
        abort "IP is not associated to any instance".color :yellow
      end
    else
      abort "Invalid IP address format".color :red
    end
  end

  desc "release","release an elastic ip"
  option :region,
         aliases: "-r",
         desc: "region to used if specified"
  option :eip,
         aliases: "-e",
         required: true,
         desc: "elastic ip to destroy"
  def release
    ec2 = create_connection
    if options[:region]
      abort "invalid region name: #{options[:region]}" unless ec2.regions.map(&:name).include?(options[:region].to_s)
      ec2 = ec2.regions[options[:region]]
    end
    #validate ipaddr
    if valid_ipv4?(options[:eip])
      abort "Elastic IP not found".color :red unless ec2.elastic_ips.map(&:public_ip).include?(options[:eip].to_s)
      eip = ec2.elastic_ips[options[:eip]]
      if eip.associated?
        puts "Elastic IP is already assicated with #{eip.instance.id}, disassciate the ip first".color :yellow
      else
        eip.release
        puts "Released IP: #{options[:eip]}".color :green
      end
    else
      abort "Invalid IP address format".color :red
    end
  end # => release

  private

  def valid_ipv4?(ipaddr)
    # => Method to validate ipv4 address
    if /\A(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\Z/ =~ ipaddr
      return $~.captures.all? {|i| i.to_i < 256}
    else
      false
    end
  end
end # => ElasticIP

class SpotInstances < Thor
  desc "list [REGION]", "list all spot requests, limited by REGION if omitted lists default region"
  option :region,
         aliases: "-r",
         desc: "specify region explicitly"
  def list
    ec2 = create_connection
    if options[:region]
      abort "invalid region name: #{options[:region]}" unless ec2.regions.map(&:name).include?(options[:region].to_s)
      ec2 = ec2.regions[options[:region]]
    end
    # => To list all
    # ec2.client.describe_spot_instance_requests
    # => To list specific spot request
    # sr = ec2.client.describe_spot_instance_requests(:spot_instance_request_ids => ["sir-35175014"])
    table = Terminal::Table.new :title => "Spot Requests Overview",
                   :headings => ['Request Id', 'Max Price', 'Instance ID', 'AMI ID', 'Type', 'State', 'Status', 'Desc', 'Group'] do |t|
      ec2.client.describe_spot_instance_requests.data[:spot_instance_request_set].each do |sr|
        t << [sr[:spot_instance_request_id],
            sr[:spot_price],
            sr[:instance_id],
            sr[:launch_specification][:image_id],
            sr[:launch_specification][:instance_type],
            sr[:state],
            sr[:status][:code],
            sr[:product_description],
            sr[:launch_group],
           ]
      end
    end
    puts table
  end # => list

  desc "cancel [SPOTID]", "cancel a specified spot request"
  option :region,
         aliases: "-r",
         desc: "specify region explicitly"
  option :spot_id,
         aliases: "-s",
         type: :array,
         desc: "spot request id(s) to cancel"
  option :all,
         aliases: "-a",
         type: :boolean,
         default: false,
         desc: "deletes all available spot requests"
  def cancel
    ec2 = create_connection
    if options[:region]
      abort "invalid region name: #{options[:region]}" unless ec2.regions.map(&:name).include?(options[:region].to_s)
      ec2 = ec2.regions[options[:region]]
    end
    available_spot_ids = ec2.client.describe_spot_instance_requests.data[:spot_instance_request_set].map {
      |k| k[:spot_instance_request_id]
    }
    if options[:spot_id]
      #validate spotrequest ids
      options[:spot_id].each do |sid|
        abort "Spot id #{sid} not found!".color :red unless available_spot_ids.include? sid
      end
    end
    if options[:all] # => Cancel passed spot_requests
      # => Cancel all spot requests available
      puts "(Warning) This will cancel all spot requests".color :yellow
      abort unless ask("Are you sure you want to continue? ", :limited_to => ["yes", "no"]) == "yes"
      ec2.client.cancel_spot_instance_requests(:spot_instance_request_ids => available_spot_ids)
      puts "This will only cancel the spot requests but will not actually terminate the instances associated. Instances "\
           "should be manually terminted".color :yellow
    elsif options[:spot_id]
      puts "Cancelling spot_id(s): " + options[:spot_id].join(",")
      ec2.client.cancel_spot_instance_requests(:spot_instance_request_ids => options[:spot_id])
      puts "This will only cancel the spot requests but will not actually terminate the instances associated. Instances "\
           "should be manually terminted".color :yellow
    else
      puts "should either pass '--spot-id=id1 id2 id3' to cancel repective spot requests "\
           " (or) '--all'  to cancel all the spot requests".color :yellow
    end
  end # => cancel
end # => SpotInstances

class AwsCmd < Thor
  desc "elasticip [SUBCOMMANDS]", "elasticip management"
  subcommand "elasticip", ElasticIp

  desc "spotinstances [SUBCOMMANDS]", "spot instances management"
  subcommand "spotinstances", SpotInstances

  desc "list [REGION] [OPTIONS]", "list all instances/sec_groups/key_pairs, limited by REGION if omitted uses default region"
  option :region,
         aliases: "-r",
         desc: "specify region from which to list instances from"
  option :sec_groups,
         aliases: "-s",
         type: :boolean,
         default: false,
         desc: "list available security groups"
  option :key_pairs,
         aliases: "-k",
         type: :boolean,
         default: false,
         desc: "list available key pairs"
  option :instance_prices,
         aliases: "-p",
         type: :boolean,
         default: false,
         desc: "list on-demand instance prices"
  def list
    ec2 = create_connection       # intialize connection
    if options[:region]
      abort "invalid region name: #{options[:region]}" unless ec2.regions.map(&:name).include?(options[:region].to_s)
      ec2 = ec2.regions[options[:region]]
    end
    list_all ec2
  end # => list

  desc "create [OPTIONS]", "Creates new instance(s)"
  option :ami_id,
         aliases: "-a",
         desc: "amazon machine image id to use"
  option :num_of_instances,
         type: :numeric,
         aliases: "-n",
         desc: "number of instances to request/create"
  option :region,
         aliases: "-r",
         desc: "region in which the instance should be created"
  option :key_pair,
         aliases: "-k",
         desc: "key pair to use for the instance, if omitted will create a new key pair"
  option :upload_keypair,
         desc: "upload existing keypair from the path specified"
  option :sec_group,
         aliases: "-s",
         desc: "security group to use for the instance, if omitted will use default"
  option :spot_instance,
         type: :boolean,
         default: false,
         desc: "Requests spot instances, requires a spot bid price"
  option :describe_spot_price_history,
         type: :boolean,
         default: false,
         aliases: "-d",
         desc: "describes spot history prices"
  option :instance_type,
         aliases: "-t",
         desc: "instance size to use, ex: m1.small (default)"
  option :elastic_ip,
         type: :boolean,
         default: false,
         desc: "assigns an elastic ip to the instance if set"
  def create
    ec2 = create_connection
    if options[:region]
      abort "invalid region name: #{options[:region]}" unless ec2.regions.map(&:name).include?(options[:region].to_s)
      ec2 = ec2.regions[options[:region]]
    end
    create_instances ec2
  end

  desc "restart", "Starts a stopped isntance"
  option :instance_id,
         required: true,
         aliases: "-i"
  option :region,
         aliases: "-r",
         desc: "pass a region (optional)"
  def restart
    ec2 = create_connection
    if options[:region]
      abort "invalid region name: #{options[:region]}" unless ec2.regions.map(&:name).include?(options[:region].to_s)
      ec2 = ec2.regions[options[:region]]
    end
    start_stopped_instance ec2
  end

  desc "terminate", "Terminates a running/stopped instance"
  option :instance_id,
         aliases: "-i",
         desc: "instance id to terminate"
  option :region,
         aliases: "-r",
         desc: "pass a region (optional)"
  option :all,
         aliases: "-a",
         type: :boolean,
         default: false,
         desc: "will terminate all the isntances (Danger)"
  def terminate
    ec2 = create_connection
    if options[:region]
      abort "invalid region name: #{options[:region]}" unless ec2.regions.map(&:name).include?(options[:region].to_s)
      ec2 = ec2.regions[options[:region]]
    end
    terminate_instance ec2
  end

  desc "stop", "Stops a running instance"
  option :instance_id,
         required: true,
         aliases: "-i",
         desc: "isntance id to stop"
  option :region,
         aliases: "-r",
         desc: "pass a region (optional)"
  def stop
    puts "stop #{options.inspect}"
    ec2 = create_connection
    if options[:region]
      abort "invalid region name: #{options[:region]}" unless ec2.regions.map(&:name).include?(options[:region].to_s)
      ec2 = ec2.regions[options[:region]]
    end
    stop_running_instance ec2
  end

  private

  def list_all ec2
    # => List instances/security groups/keys based on region if passed using thor options
    if options[:sec_groups]
      # => Security Groups
      table = Terminal::Table.new :title => "Security Groups Overview",
                                  :headings => ['ID', 'NAME', 'Description'] do |row|
        AWS::memoize do
          ec2.security_groups.each do |sg|
            row << [sg.id, sg.name, sg.description]
          end
        end
      end
      puts table
    elsif options[:key_pairs]
      # => Key Pairs
      table = Terminal::Table.new :title => "Key Pairs Overview",
                                  :headings => ['NAME', 'Fingerprint'] do |row|
        AWS::memoize do
          ec2.key_pairs.each do |kp|
            row << [kp.name, kp.fingerprint]
          end
        end
      end
      puts table
    elsif options[:instance_prices]
      # => List Instance Pricing
      puts "Using Region: #{options[:region]}"
      @@Api_Name_Lookup = {
        'stdODI' => {'sm' => 'm1.small', 'med' => 'm1.medium', 'lg' => 'm1.large', 'xl' => 'm1.xlarge'},
        'hiMemODI' => {'xl' => 'm2.xlarge', 'xxl' => 'm2.2xlarge', 'xxxxl' => 'm2.4xlarge'},
        'hiCPUODI' => {'med' => 'c1.medium', 'xl' => 'c1.xlarge'},
        'hiIoODI' => {'xxxxl' => 'hi1.4xlarge'},
        'clusterGPUI' => {'xxxxl' => 'cg1.4xlarge'},
        'clusterComputeI' => {'xxxxl' => 'cc1.4xlarge','xxxxxxxxl' => 'cc2.8xlarge'},
        'uODI' => {'u' => 't1.micro'},
        'secgenstdODI' => {'xl' => 'm3.xlarge', 'xxl' => 'm3.2xlarge'},
        'clusterHiMemODI' => {'xxxxxxxxl' => 'cr1.8xlarge'},
        'hiStoreODI' => {'xxxxxxxxl' => 'hs1.8xlarge'},
      }
      pricing = open('http://aws.amazon.com/ec2/pricing/pricing-on-demand-instances.json') { |f| f.read }
      parsed_pricing = JSON.parse(pricing)

      table = Terminal::Table.new :title => "Prices Overview",
                                  :headings => ['Instance Tpye', 'OS', 'Price'] do |row|
        parsed_pricing["config"]["regions"].each do |rg|
          rg["instanceTypes"].each do |inst|
            # puts "Instace Category: #{inst["type"]}"
            inst["sizes"].each do |size|
              size["valueColumns"].each do |f|
                # puts "Instance Type: #{@@Api_Name_Lookup[inst["type"]][size["size"]]}, Instance OS: #{f["name"]}, Instance Price: #{f["prices"]["USD"]}, Region: #{rg["region"]}"
                row << [@@Api_Name_Lookup[inst["type"]][size["size"]], f["name"], f["prices"]["USD"]]
              end
            end
          end
        end
      end
      puts table
    else
      # => Instances
      table = Terminal::Table.new :title => "Instances Overview",
                                  :headings => ['Instance ID', 'Status', 'Type', 'DNS_NAME', 'IP_ADD', 'ARCH',
                                                'IMG_ID', 'KEY', 'SPOT_INSTANCE?', 'Name_Tags'] do |row|
      AWS::memoize do
        ec2.instances.each do |i|
          row << [i.id, i.status, i.instance_type, i.dns_name, i.ip_address, i.architecture, i.image_id,
                i.key_name, i.spot_instance?, i.tags.map { |k, v| v }.join(",")]
          end
        end
      end
      puts table
    end
  end # => list_instances

  def create_instances ec2
    #check spot instance
    if options[:spot_instance]
      puts "(Warning) Spot instances do not gaurentee the servers availability immediately".color :yellow
      abort unless ask("Are you sure you want to continue? ", :limited_to => ["yes", "no"]) == "yes"
      #ask spot bid price
      @spot_bid = ask("Enter maximum spot bid price: ")
      abort "Invalid bid price entered!".color :red unless @spot_bid =~ /(\d+\.\d+)/
    end
    #check instance type
    if options[:instance_type]
      available_instance_types = %w(t1.micro m1.small m1.medium m1.large m1.xlarge m3.xlarge m3.2xlarge m2.xlarge
                                    m2.2xlarge m2.4xlarge c1.medium c1.xlarge hs1.8xlarge)
      if available_instance_types.include?(options[:instance_type])
        instance_type = options[:instance_type]
      else
        puts "Invalid instance_type #{options[:instance_type]}".color :red
        puts "Available instance types are: " + available_instance_types.join(",")
        abort
      end
    else
      instance_type = "m1.small"
    end
    #output spot price history
    if options[:describe_spot_price_history]
      # puts "Spot price history:"
      # puts ec2.client.describe_spot_price_history
      history = ec2.client.describe_spot_price_history(:instance_types => [instance_type],
                                             :max_results => 1000,
                                             :start_time => (DateTime.now - 7).iso8601, #Data from a week
                                             :end_time => DateTime.now.iso8601,
                                             :product_descriptions=>["Linux/UNIX"],
                                            )
      #get spot_prices from inner hash
      history[:spot_price_history_set].each do |set|
        (@price_set ||= []) << set[:spot_price].to_f
      end
      puts "Avg spot bid price for instance_type for the past week '#{instance_type}' is: " +
          (@price_set.inject(0.0) { |sum, el| sum + el } / @price_set.size).round(3).to_s.color(:green)
      exit
    end

    puts "Instance type is: #{instance_type}"

    #instance count
    instance_count = options[:num_of_instances] || 1
    puts "Instance count is: #{instance_count}"

    #select amazon linux image if nothing is specified
    unless options[:ami_id]
      image = AWS.memoize do
        amazon_linux = ec2.images.with_owner("amazon").filter("root-device-type", "ebs").
                                                       filter("architecture", "x86_64").
                                                       filter("name", "amzn-ami*")
        amazon_linux.to_a.sort_by(&:name).last
      end
      puts "Using AMI: #{image.name} with ID: #{image.id}"
    else
      #validate AMI
      image = ec2.images[options[:ami_id]]
      abort "Cannot find AMI with id: #{options[:ami_id]}".color :red unless image.exists?
      puts "Using AMI: #{image.id} with Name: #{image.name}"
    end

    #create a new keypair if not passed
    unless options[:key_pair]
      key_pair_tmp = "ruby-sample-#{Time.now.to_i}"
      key_pair = ec2.key_pairs.create(key_pair_tmp)
      puts "Generated new Keypair #{key_pair.name} with fingerprint: #{key_pair.fingerprint}"
      puts "Downloading Keypair to users .ssh/#{key_pair_tmp}"
      File.open(File.expand_path('~/.ssh/' + key_pair_tmp), 'w') do |f|
        f << key_pair.private_key
      end
      File.chmod(0600, File.expand_path('~/.ssh/' + key_pair_tmp))
    else
      #validate keypair
      key_pair = ec2.key_pairs[options[:key_pair]]
      abort "Cannot find keypair: #{options[:key_pair]}, please use '#{__FILE__}' list --key-pairs, to see "\
            "available key pairs".color :red unless key_pair.exists?
      puts "Using key pair #{options[:key_pair]}"
    end

    #import a keypair if specified
    if options[:upload_keypair]
      #check if keypair is present
      abort "Cannot find key file #{options[:upload_keypair]}".color :red unless File.exist?(options[:upload_keypair])
      key_pair = ec2.key_pairs.import("ruby-sample-#{Time.now.to_i}", File.read(options[:upload_keypair]))
    end

    #create security_group if not passed
    unless options[:sec_group]
      sec_grp_tmp = "ruby-sample-#{Time.now.to_i}"
      puts "Creating new security group #{sec_grp_tmp}"
      group = ec2.security_groups.create(sec_grp_tmp)
      group.authorize_ingress(:tcp, 22, "0.0.0.0/0")
      puts "Created security group #{group.name}"
    else
      #validate security group
      group = ec2.security_groups[options[:sec_group]]
      abort "Cannot find security group with id: #{options[:sec_group]}, please use '#{__FILE__} list --sec-groups', "\
            "to see available groups".color :red unless ec2.security_groups.map(&:id).include?(options[:sec_group].to_s)
      puts "Using seurity group #{group.id}"
    end

    # => Creates intance(s)
    unless options[:spot_instance]
      # => on-demand instances
      (1..instance_count).each do |count|
        instance = ec2.instances.create(
                    :image_id => image.id,
                    :instance_type => instance_type,
                    :security_groups => group,
                    :key_pair => key_pair,
                    )
        instance.tags["Name"] = "ruby-sample-#{Time.now.to_i}-#{count}"
        (@instances ||= []) << instance
      end

      @instances.each do |i|
        sleep 10 while i.status == :pending
        puts "Launched instance #{i.id}, status: #{i.status}".color :green
        if options[:elastic_ip]
          # => associate elastic ip to all instance
          eip = ec2.elastic_ips.allocate
          eip.associate :instance => i
          puts "ElasticIP: #{eip.public_ip} is associated to instance: #{i.id}".color :green
        end
      end
    else
      # => spot instances
      launch_group = "ruby-sample-#{Time.now.to_i}"
      response = ec2.client.request_spot_instances(
        :spot_price => @spot_bid.to_s,
        :instance_count => instance_count,
        #:type -> (String) Specifies the Spot Instance type.
        #:valid_from -> (String<ISO8601 datetime>) Defines the start date of the request. If this is a one-time request,
        # the request becomes active at this date and time and remains active until all instances launch,
        # the request expires
        #:valid_until -> (String<ISO8601 datetime>) End date of the request. If this is a one-time request, the request
        # remains active until all instances launch, the request is canceled, or this date is reached
        #:launch_group - (String) Specifies the instance launch group. Launch groups are Spot Instances that launch
        # and terminate together
        :launch_group => launch_group,
        :launch_specification => {
          :image_id => image.id,
          :instance_type => instance_type,
          :key_name => key_pair.name.to_s,
          :security_groups => group.name.to_s.split, #this only takes enumerable
        }
      )
      puts response.spot_instance_request_set.map(&:spot_instance_request_id)
      puts "Use '#{__FILE__} spotinstances list' to monitor the spot request progress".color :green
    end

    #Check running command on newly created instance if they are amazon linux image
    #This has issues -> if keypair is passed by user it will not allow to use private_key, private_key is only availble
    #if you generate the private key
    # unless options[:ami_id]
    #   @instances.each do |i|
    #     begin
    #       Net::SSH.start(i.ip_address, "ec2-user",
    #                       :key_data => [key_pair.private_key]) do |ssh|
    #         puts "Running 'uname -a' on the instance #{i.id} yeilds:"
    #         puts ssh.exec!("uname -a")
    #       end
    #     rescue SystemCallError, Timeout::Error
    #       #port 22 might not be available immediately after instance finshes launching
    #       sleep 1
    #       retry
    #     end
    #   end
    # end
    #More Options: http://docs.aws.amazon.com/AWSRubySDK/latest/AWS/EC2/InstanceCollection.html
  end # => create_instances

  def start_stopped_instance ec2
    # => Restart an instance which is stopped
    instance = ec2.instances[options[:instance_id]]
    if instance.exists?
      #intance exists
      if instance.status.to_s == "stopped"
        if ask("Are you sure do you want to start the instance #{options[:instance_id]}? ",
                                                                                :limited_to => ["yes", "no"]) == "yes"
          puts "starting instance #{options[:instance_id]} ..."
          instance.start
        end
      else
        puts "Instance is already running state"
      end
    else
      #instance not found, reason may be check in other region or instance does not exists altogether
      puts "instance cannot not found in default region, please pass region if the instance exists other than default"\
           "region"
    end
  end # => start_stopped_instance

  def stop_running_instance ec2
    # => Stop a running instance
    instance = ec2.instances[options[:instance_id]]
    if instance.exists?
      if instance.status.to_s == "running"
        if ask("Are you sure you want to stop the instance #{options[:instance_id]}? ",
                                                                                :limited_to => ["yes", "no"]) == "yes"
          puts "stopping instance #{options[:instance_id]} ..."
          instance.stop
        end
      else
        puts "Instance is already stopped"
      end
    else
      puts "instance cannot not found in default region, please pass region if the instance exists other than default"\
           "region"
    end
  end # => stop_running_instance

  def terminate_instance ec2
    # => Terminates a running/stopped instance
    abort "Should either pass '--instance-id' or '-all'".color :red unless options[:instance_id] or options[:all]
    if options[:instance_id]
      # => Termiante single instance
      instance = ec2.instances[options[:instance_id]]
      if instance.exists?
        if instance.status.to_s == "running" or instance.status.to_s == "stopped"
          puts "(Warning) Terminating an instance will result in loss of data".color :yellow
          if ask("Are you sure do you want to continue?", :limited_to => ["yes", "no"]) == "yes"
            puts "Terminating instance #{options[:instance_id]} ..."
            instance.terminate
          end
        else
          puts "Instance #{options[:instance_id]} is in #{instance.status.to_s} state"
        end
      else
        puts "instance cannot not found in default region, please pass '--region' if the instance exists other than "\
              "default region"
      end
    elsif options[:all]
      # => Terminate all running instances
      puts "(Warning) This will Terminate all the running/stopped isntances".color :yellow
      if ask("Are you sure you want to continue? ", :limited_to => ["yes", "no"]) == "yes"
        AWS::memoize do
          ec2.instances.map(&:id).each do |inst|
            instance = ec2.instances[inst]
            if instance.status.to_s == "running" or instance.status.to_s == "stopped"
              puts "Terminating instance #{inst}"
              instance.terminate
            end
          end
        end
      end
    end
  end # => terminate_instance

end # => AwsCmd

AwsCmd.start ARGV