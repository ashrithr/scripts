#!/usr/bin/env ruby
# ---
# => Script to generate random data required for data analytics
# ---
require 'rubygems'
require 'fileutils'
require 'benchmark'
require 'parallel'          #gem install parallel
require 'ruby-progressbar'  #gem install ruby-progressbar
require 'optparse'

abort "Only works with ruby 1.9" if RUBY_VERSION < "1.9"

# => Command line Arguments
@options = {}
option_parser = OptionParser.new do |opts|
  executable_name = File.basename($PROGRAM_NAME)
  opts.banner = "Usage: #{executable_name} [options]"

  opts.on("-l LINES", "--lines LINES",
    "number of lines to generate to analytics file") do |lines|
    @options[:lines] = lines.to_i
  end

  opts.on("-m", "--multiple-tables", "Generate data for hive") do
    @hive_data = true
  end

  opts.on("-p PATH", "--output-path PATH",
    "Path where output should be generated to") do |path|
    @options[:path] = path
  end

  opts.on("-e", "--extra-data", "generate extra data") do
    @extras = true
  end

  opts.on("-h","--help","Help") do
    puts option_parser
    abort
  end
end # => end option_parser

begin
  option_parser.parse!
rescue OptionParser::ParseError => e
  STDERR.puts e.message
  STDERR.puts option_parser
  exit 1
end

unless @options.has_key?(:lines)
  STDERR.puts 'Missing required argument --lines or -l'
  STDERR.puts option_parser
  exit 1
end # => end option_parser logic

# => Globals
@lines = @options[:lines]                  #No. of lines to generate
@lines_per_process = 500000                #lines to gen by indvidual process
@num_of_processes = @lines > @lines_per_process ?
                    @lines / @lines_per_process :
                    1                     #num_of_processes required to compute
@options[:path] = "/tmp" unless @options.has_key?(:path)
                                          #Output path
@cd = "\t"                                 #column delimeter
@ld = "\n"                                #line delimeter
#@extras = false                           #generate extra data : name, phoneno,
                                            # email, address
@cid_start = 1000                         #Customer id start int
@gender_with_probability = {              #Gender hash with probability
  :male   => 30,
  :female => 70
}
@lifetime_days = 90                       #Life time in days
@friendcount_maxrange = 100               #Friends count maximum range
@friendcount_zero_probability = 0.3       #30% of times users dont have friends
@paid_subscriber_percent = 0.5           #5% users are paid customers
@paid_subscriber_frndcount = 5            #users whose frnd_cnt > 5 pay
@age_with_probability = {                 #Age hash with probability
  18 => 15,
  19 => 12,
  20 => 12,
  21 => 11,
  22 => 11,
  23 => 9,
  24 => 7,
  25 => 6,
  26 => 5,
  27 => 4,
  28 => 3,
  29 => 2,
  30 => 2,
}
@countries_with_probability = {           #Countries hash with probabilities
  "USA"      => 60,
  "UK"       => 25,
  "CANADA"   => 5,
  "MEXICO"   => 5,
  "GERMANY"  => 10,
  "FRANCE"   => 10,
  "EGYPT"    => 5
}
@games_female = {
  :city       => 50,
  :pictionary => 30,
  :scramble   => 15,
  :sniper     => 5,
}
@games_male = {
  :sniper     => 70,
  :scramble   => 20,
  :pictionary => 10,
  :city       => 10,
}

# => Definations
def choose_weighted(weighted)
  # => Returns value picked from hash passed randomly based on its weight
  #    All the weights in the hash must be integers
  # Ex: marbles = { :black => 51, :white => 17 }
  #     3.times { puts choose_weighted(marbles) }

  #caluculate the total weight
  sum = weighted.inject(0) do |sum, item_and_weight|
    sum += item_and_weight[1]
  end
  #assign a random from total weight to target
  target = rand(sum)
  #return a value based on its weight
  weighted.each do |item, weight|
    return item if target <= weight
    target -= weight
  end
end

def gen_phone_num
  # => Returns a random phone number
  "#{rand(900) + 100}-#{rand(900) + 100}-#{rand(1000) + 1000}"
end

def gen_int_phone_num
  # => Returns a random international phone number
  "011-#{rand(100) + 1}-#{rand(100) + 10}-#{rand(1000) + 1000}"
end

def gen_email(name)
  # => Returns a random email based on the usersname
  firstname = name.split.first
  lastname = name.split.last
  domains = %w(yahoo.com gmail.com privacy.net webmail.com msn.com
               hotmail.com example.com privacy.net)
  return "#{(firstname + lastname).downcase}"\
         "#{rand(100)}\@#{domains[rand(domains.size)]}"
end

def gen_date(from=0.0, to=Time.now)
  # => Returns a random date, also can specify range to it
  # Ex: gen_date
  #     gen_date(Time.local(2010, 1, 1))
  #     gen_date(Time.local(2010, 1, 1), Time.local(2010, 7, 1))
  Time.at(from + rand * (to.to_f - from.to_f))
end

class Names
  # => Class that will return some random names based on gender
  def self.initial
    letters_arr = ('A'..'Z').to_a
    letters_arr[rand(letters_arr.size)]
  end
  @@lastnames = %w(ABEL ANDERSON ANDREWS ANTHONY BAKER BROWN BURROWS CLARK
                   CLARKE CLARKSON DAVIDSON DAVIES DAVIS DENT EDWARDS GARCIA
                   GRANT HALL HARRIS HARRISON JACKSON JEFFRIES JEFFERSON JOHNSON
                   JONES KIRBY KIRK LAKE LEE LEWIS MARTIN MARTINEZ MAJOR MILLER
                   MOORE OATES PETERS PETERSON ROBERTSON ROBINSON RODRIGUEZ
                   SMITH SMYTHE STEVENS TAYLOR THATCHER THOMAS THOMPSON WALKER
                   WASHINGTON WHITE WILLIAMS WILSON YORKE)
  def self.lastname
    @@lastnames[rand(@@lastnames.size)]
  end
  @@male_first_names =
    %w(ADAM ANTHONY ARTHUR BRIAN CHARLES CHRISTOPHER DANIEL DAVID DONALD EDGAR
       EDWARD EDWIN GEORGE HAROLD HERBERT HUGH JAMES JASON JOHN JOSEPH KENNETH
       KEVIN MARCUS MARK MATTHEW MICHAEL PAUL PHILIP RICHARD ROBERT ROGER RONALD
       SIMON STEVEN TERRY THOMAS WILLIAM)

  @@female_first_names =
    %w(ALISON ANN ANNA ANNE BARBARA BETTY BERYL CAROL CHARLOTTE CHERYL DEBORAH
       DIANA DONNA DOROTHY ELIZABETH EVE FELICITY FIONA HELEN HELENA JENNIFER
       JESSICA JUDITH KAREN KIMBERLY LAURA LINDA LISA LUCY MARGARET MARIA MARY
       MICHELLE NANCY PATRICIA POLLY ROBYN RUTH SANDRA SARAH SHARON SUSAN
       TABITHA URSULA VICTORIA WENDY)

  def self.female_name
    # => Returns a female name
    "#{@@female_first_names[rand(@@female_first_names.size)]} #{lastname}"
  end

  def self.male_name
    # => Returns a male name
    "#{@@male_first_names[rand(@@male_first_names.size)]} #{lastname}"
  end
end

class Address
  # => Class that will return some random based addresses now only supports USA
  # and UK addresses
  @@street_names = %w( Acacia Beech Birch Cedar Cherry Chestnut Elm Larch Laurel
    Linden Maple Oak Pine Rose Walnut Willow Adams Franklin Jackson Jefferson
    Lincoln Madison Washington Wilson Churchill Tyndale Latimer Cranmer Highland
    Hill Park Woodland Sunset Virginia 1st 2nd 4th 5th 34th 42nd
    )
  @@street_types = %w( St Ave Rd Blvd Trl Rdg Pl Pkwy Ct Circle )

  def self.address_line_1
    # => Returns address line 1
    "#{rand(4000)} #{@@street_names[rand(@@street_names.size)]}"\
      " #{@@street_types[rand(@@street_types.size)]}"
  end

  @@line2types = ["Apt", "Bsmt", "Bldg", "Dept", "Fl", "Frnt", "Hngr", "Lbby",
    "Lot", "Lowr", "Ofc", "Ph", "Pier", "Rear", "Rm", "Side", "Slip", "Spc",
    "Stop", "Ste", "Trlr", "Unit", "Uppr"]

  def self.address_line_2
    # => Returns address line 2
    "#{@@line2types[rand(@@line2types.size)]} #{rand(999)}"
  end

  def self.zipcode
    # => Returns a zip code
    "%05d" % rand(99999)
  end

  def self.uk_post_code
    # => Returns UK Zip code
    post_towns = %w(BM CB CV LE LI LS KT MK NE OX PL YO)
    num1 = rand(100).to_s
    num2 = rand(100).to_s
    letters_arr = ("AA".."ZZ").to_a
    letters = letters_arr[rand(letters_arr.size)]
    return "#{post_towns[rand(post_towns.size)]}#{num1} #{num2}#{letters}"
  end

  @@us_states = ["AK", "AL", "AR", "AZ", "CA", "CO", "CT", "DC", "DE", "FL",
                 "GA", "HI", "IA", "ID", "IL", "IN", "KS", "KY", "LA", "MA",
                 "MD", "ME", "MI", "MN", "MO", "MS", "MT", "NC", "ND", "NE",
                 "NH", "NJ", "NM", "NV", "NY", "OH", "OK", "OR", "PA", "RI",
                 "SC", "SD", "TN", "TX", "UT", "VA", "VT", "WA", "WI", "WV",
                 "WY"]
  def self.state
    # => Returns a state
    @@us_states[rand(@@us_states.size)]
  end
end #end Locations

# => MAIN LOOP
def main_loop(num_of_lines, cid_start, proc, progress=true)
  counter = cid_start + (num_of_lines - 1)

  #initialize the progressbar if progress = true
  progressbar = ProgressBar.create(:total => num_of_lines,
                                   :format => '%a |%b>>%i| %p%% %t') if progress

  #Create output dir if does not exist
  FileUtils.mkdir_p(@options[:path]) unless File.exists?(@options[:path])
  #File Management
  if @hive_data
    cust_table = "#{@options[:path]}/analytics_customer#{proc}.data"
    revn_table = "#{@options[:path]}/analytics_revenue#{proc}.data"
    fact_table = "#{@options[:path]}/analytics_facts#{proc}.data"

    cust_file_handle = File.open(cust_table, "w")
    revn_file_handle = File.open(revn_table, "w")
    fact_file_handle = File.open(fact_table, "w")
  else
    output_file = "#{@options[:path]}/analytics_#{proc}.data"
    output_file_handle = File.open(output_file, "w")
  end

  #header for the file
  # if @hive_data
  #   cust_file_handle.
  #     puts("cid#{@cd}name#{@cd}gender#{@cd}age#{@cd}rdate#{@cd}country#{@cd}"\
  #       "friend_count#{@cd}lifetime")
  #   revn_file_handle.puts("cid#{@cd}pdate#{@cd}usd")
  #   fact_file_handle.puts("cid#{@cd}game_played#{@cd}gdate")
  # else
  if !@hive_data
    @extras ?
    output_file_handle.puts("cid#{@cd}gender#{@cd}age#{@cd}country#{@cd}"\
    "registerdate#{@cd}name#{@cd}email#{@cd}phone#{@cd}address#{@cd}"\
    "friend_count#{@cd}lifetime"\
    "#{@cd}citygame_played#{@cd}pictionarygame_played#{@cd}scramblegame_played"\
    "#{@cd}snipergame_played#{@cd}revenue#{@cd}paid") :
    output_file_handle.puts("cid#{@cd}gender#{@cd}age#{@cd}country#{@cd}"\
    "registerdate#{@cd}friend_count#{@cd}lifetime#{@cd}citygame_played#{@cd}"\
    "pictionarygame_played#{@cd}scramblegame_played#{@cd}snipergame_played"\
    "#{@cd}revenue#{@cd}paid")
  end # => End header generation

  (cid_start..counter).each do |cid|
    # => gender
    gender = choose_weighted(@gender_with_probability)
    # => Registration date(generate date from 2010-1-1 to now)
    register_date = gen_date(Time.local(2011, 1, 1))
    year = register_date.year
    month = register_date.month
    day = register_date.day
    # => age
    age = choose_weighted(@age_with_probability)
    # => country
    country = choose_weighted(@countries_with_probability)
    name = gender == :male ? Names.male_name : Names.female_name
    email = gen_email(name)
    phone = country == "USA" ? gen_phone_num : gen_int_phone_num
    case country
    when "USA"
      address = "#{Address.address_line_1} #{Address.address_line_2}"\
                " #{Address.state} #{Address.zipcode}"
    when "UK"
      address = "#{Address.address_line_1} #{Address.address_line_2}"\
                " #{Address.uk_post_code}"
    when "CANADA"
      address = "N/A"
    when "MEXICO"
      address = "N/A"
    when "GERMANY"
      address = "N/A"
    when "FRANCE"
      address = "N/A"
    else  #egypt
      address = "N/A"
    end
    # => total_days user played
    total_days = rand(@lifetime_days)
    # => friends_count
    if rand < @friendcount_zero_probability
      #30% of users do not have friends at all
      friend_count = 0
    else
      #10% of users will have fried count >5 and other will be friend < 5
      rand < 0.2 ?
        friend_count = rand(@paid_subscriber_frndcount..@friendcount_maxrange) :
        friend_count = rand(0..@paid_subscriber_frndcount)
    end
    # => paid customer
    if ( friend_count > 5 and total_days > 10 )
      if rand < @paid_subscriber_percent
        paid_subscriber = "yes"
      else
        paid_subscriber = "no"
      end
    else
      paid_subscriber = "no"
    end
    # ( friend_count > 5 and total_days > 10 ) ? paid_subscriber = "yes" :
    #                                            paid_subscriber = "no"
    # => revenue
    if paid_subscriber == "yes"
      rand < 0.8 ? revenue = rand(5..30) : revenue = rand(30..99)
    else
      revenue = 0
    end
    # => Paid_date
    revenue == 0 ? paid_date = 0 :
                  paid_date = gen_date(Time.local(year, month, day), Time.now)
    # => games_played by user
      #intialize gamecounters
    city_counter = 0
    pictionary_counter = 0
    sniper_counter = 0
    scramble_counter = 0
    gender_game_hash = gender == :male ? @games_male : @games_female
    total_days.times do
      case choose_weighted(gender_game_hash)
      when :citygame
        city_counter += 1
      when :pictionary
        pictionary_counter += 1
      when :scramble
        scramble_counter += 1
      else
        sniper_counter += 1
      end
    end

    # => build final strings
    if @hive_data
      (customer_tbl ||= "") << "#{cid}" << @cd << "#{name}" << @cd <<
                            "#{gender}" << @cd << "#{age}" << @cd <<
                            "#{register_date.strftime("%Y-%m-%d %H:%M:%S")}" <<
                             @cd << "#{country}" << @cd << "#{friend_count}" <<
                             @cd << "#{total_days}"
      (revenue_tbl ||= "") << "#{cid}" << @cd <<
                           "#{paid_date.strftime("%Y-%m-%d %H:%M:%S")}" <<
                           @cd << "#{revenue}" unless revenue == 0
      #array to store strings
      gender_game_hash = gender == :male ? @games_male : @games_female
      fact_tbl_arr = []
      # num_of_times_played = rand < 0.9 ? rand(1..100) : rand(1..300)
      total_days.times do
        # => Played_date
        played_date = gen_date(Time.local(year, month, day),
                                                      Time.local(2012, 12, 31))
        (fact_tbl ||= "") << "#{cid}" << @cd <<
                          "#{choose_weighted(gender_game_hash)}" << @cd <<
                          "#{played_date.strftime("%Y-%m-%d %H:%M:%S")}"
        fact_tbl_arr << fact_tbl
      end

    else
      if @extras
        ( final_string ||= "" ) << "#{cid}" << @cd << "#{gender}" << @cd <<
                                "#{age}" << @cd << "#{country}" << @cd <<
                                "#{register_date}" << @cd <<
                                "#{name}" << @cd << "#{email}" << @cd <<
                                "#{phone}" << @cd << "#{address}" << @cd <<
                                "#{friend_count}" << @cd << "#{total_days}" <<
                                @cd << "#{city_counter}" <<
                                @cd << "#{pictionary_counter}" << @cd <<
                                "#{scramble_counter}" << @cd <<
                                "#{sniper_counter}" << @cd << "#{revenue}" <<
                                @cd << "#{paid_subscriber}"
      else
        ( final_string ||= "" ) << "#{cid}" << @cd << "#{gender}" << @cd <<
                               "#{age}" << @cd << "#{country}" << @cd <<
                               "#{register_date}" << @cd <<
                               "#{friend_count}" << @cd << "#{total_days}" <<
                               @cd << "#{city_counter}" << @cd <<
                               "#{pictionary_counter}" << @cd <<
                               "#{scramble_counter}" << @cd <<
                               "#{sniper_counter}" << @cd << "#{revenue}" <<
                               @cd << "#{paid_subscriber}"
      end
    end
    # => write out to file
    if @hive_data
      cust_file_handle.puts customer_tbl
      revn_file_handle.puts revenue_tbl unless revenue == 0
      #multiple entries for fact_table
      fact_tbl_arr.each do |fact_tbl_str|
        fact_file_handle.puts fact_tbl_str
      end
    else
      output_file_handle.puts final_string
    end
    progressbar.increment if progress
  end
  # => close the file
  if @hive_data
    cust_file_handle.close
    revn_file_handle.close
    fact_file_handle.close
  else
    output_file_handle.close
  end
end #end main_loop

#Benchmark the time took to complete the program
time_took = Benchmark.measure do
  #parallel runs to_generate lines which are > than 100k
  if @num_of_processes > 1
    puts "Parallel mode, generating data to /tmp"
    progress = ProgressBar.create(:total => @num_of_processes,
                                  :format => '%a |%b>>%i| %p%% %t')
    results = Parallel.map(1..@num_of_processes,
        :finish => lambda { |i, item| progress.increment }) do |process|
      main_loop(@lines_per_process, @cid_start + (@lines_per_process* process),
        process, false)
    end
  else
    puts "Sinle process mode, generating data to #{@options[:path]}"
    if @hive_data
      (tmp_file ||= []) << "#{@options[:path]}/analytics_customer.data" <<
                           "#{@options[:path]}/analytics_revenue.data" <<
                           "#{@options[:path]}/analytics_facts.data"
    else
      (tmp_file ||= []) << "#{@options[:path]}/analytics.data"
    end
      main_loop(@lines, @cid_start, 0)
      tmp_file.clear
  end
end #benchmark end
puts "Time took to generate #{@lines} : #{time_took}"