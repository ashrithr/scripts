#!/usr/bin/env ruby
# ---
# => Script to generate random data required for data analytics
# ---
require 'rubygems'
require 'fileutils'
require 'benchmark'
require 'tempfile'
begin
  require 'parallel'
  @has_parallel = true
rescue LoadError
  @has_parallel = false
end

#Globals
@lines = 200000                             #No. of lines to generate
@output_file = "/tmp/analytics.data"      #Output file
@cd = ","                                 #column delimeter
@ld = "\n"                                #line delimeter
@extras = true                            #generate extra data : name, phoneno,
                                            # email, address
@num_of_processes = @lines > 100000 ? @lines / 100000 : 1
                                          #num_of_processes required to compute
@cid_start = 1000                         #Customer id start int
@gender = ["male", "female"]              #Gender array
@lifetime_days = 90                       #Life time in days
@friendcount_maxrange = 100               #Friends count maximum range
@gender_with_probability = {              #Gender hash with probability
  :male   => 30,
  :female => 70
}
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
@countries = [                            #Countries array
  "USA",
  "UK",
  "CANADA",
  "MEXICO",
  "GERMANY",
  "FRANCE",
  "EGYPT"
]
@countries_with_probability = {           #Countries hash with probabilities
  "USA"      => 60,
  "UK"       => 25,
  "CANADA"   => 5,
  "MEXICO"   => 5,
  "GERMANY"  => 10,
  "FRANCE"   => 10,
  "EGYPT"    => 5
}
@games = ["citygame", "sniper", "pictionary", "scramble"]
@games_female = {
  :citygame   => 50,
  :pictionary => 30,
  :scramble   => 15,
  :sniper     => 5,
}
@games_male = {
  :sniper     => 70,
  :scramble   => 20,
  :pictionary => 10,
  :citygame   => 10,
}

# => Signal Handling
Signal.trap :SIGINT do
  STDERR.puts "Ctrl+C caught killing running processes and cleaning up"
  @pids.each { |pid| Process.kill('INT', pid) } unless @pids.empty?
  @tmp_files.each { |file| FileUtils.rm_rf file } unless @tmp_files.empty?
end

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

class ParallelStuff
  def self.processor_count
    @processor_count ||= case RbConfig::CONFIG['host_os']
    when /darwin9/
      `hwprefs cpu_count`.to_i
    when /darwin/
      (hwprefs_available? ? `hwprefs thread_count` : `sysctl -n hw.ncpu`).to_i
    when /linux|cygwin/
      `grep -c processor /proc/cpuinfo`.to_i
    when /(open|free)bsd/
      `sysctl -n hw.ncpu`.to_i
    when /mswin|mingw/
      require 'win32ole'
      wmi = WIN32OLE.connect("winmgmts://")
    cpu = wmi.ExecQuery("select NumberOfLogicalProcessors from Win32_Processor")
      cpu.to_enum.first.NumberOfLogicalProcessors
    when /solaris2/
      `psrinfo -p`.to_i # this is physical cpus afaik
    else
      $stderr.puts "Unknown architecture ( #{RbConfig::CONFIG["host_os"]} )."
      1
    end
  end

  def hwprefs_available?
    `which hwprefs` != ''
  end

  def self.physical_processor_count
    @physical_processor_count ||= case RbConfig::CONFIG['host_os']
    when /darwin1/, /freebsd/
      `sysctl -n hw.physicalcpu`.to_i
    when /linux/
      `grep cores /proc/cpuinfo`[/\d+/].to_i
    when /mswin|mingw/
      require 'win32ole'
      wmi = WIN32OLE.connect("winmgmts://")
      cpu = wmi.ExecQuery("select NumberOfProcessors from Win32_Processor")
      cpu.to_enum.first.NumberOfLogicalProcessors
    else
      processor_count
    end
  end
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
    "#{@@female_first_names[rand(@@female_first_names.size)]} #{lastname}"
  end

  def self.male_name
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
    "#{rand(4000)} #{@@street_names[rand(@@street_names.size)]}"\
      " #{@@street_types[rand(@@street_types.size)]}"
  end

  @@line2types = ["Apt", "Bsmt", "Bldg", "Dept", "Fl", "Frnt", "Hngr", "Lbby",
    "Lot", "Lowr", "Ofc", "Ph", "Pier", "Rear", "Rm", "Side", "Slip", "Spc",
    "Stop", "Ste", "Trlr", "Unit", "Uppr"]

  def self.address_line_2
    "#{@@line2types[rand(@@line2types.size)]} #{rand(999)}"
  end

  def self.zipcode
    "%05d" % rand(99999)
  end

  def self.uk_post_code
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
    @@us_states[rand(@@us_states.size)]
  end
end #end Locations

# => MAIN LOOP
def main_loop(num_of_lines, output_file)
  @counter = @cid_start + num_of_lines
  #Check and output create file
  FileUtils.touch(output_file) unless File.exists? output_file

  #open up the file for writing
  output_file_handle = File.open(output_file, "w")

  #header for the file
  @extras ?
output_file_handle.puts("cid#{@cd}gender#{@cd}age#{@cd}country#{@cd}\
name#{@cd}email#{@cd}phone#{@cd}address#{@cd}friend_count#{@cd}lifetime(days)\
#{@cd}citygame_played#{@cd}pictionarygame_played#{@cd}scramblegame_played#{@cd}\
snipergame_played") :
output_file_handle.puts("cid#{@cd}gender#{@cd}age#{@cd}country#{@cd}\
friend_count#{@cd}lifetime(days)#{@cd}citygame_played#{@cd}\
pictionarygame_played#{@cd}scramblegame_played#{@cd}snipergame_played")


  time_took = Benchmark.measure do
  (@cid_start..@counter).each do |cid|
    #cust_id
    ( final_string ||= "" ) << "#{cid}"
    #gender
    #gender = @gender[rand(@gender.size)]                     #Regular case
    gender = choose_weighted(@gender_with_probability)
    final_string << @cd << "#{gender}"                        #weighted
    #age
    #age = (18 + rand(32))                                    #age between 18-50
    final_string << @cd << "#{choose_weighted(@age_with_probability)}" #weighted
    #country
    #country = @countries[rand(@countries.size)]
    country = choose_weighted(@countries_with_probability)
    final_string << @cd << country
    if @extras
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
      final_string << @cd << "#{name}" << @cd << "#{email}" << @cd <<
                    "#{phone}" << @cd << "#{address}"
    end
    #friends_count
    final_string<< @cd << "#{rand(@friendcount_maxrange)}"
    #total_hours_played_in_days
    total_hours = rand(@lifetime_days)
    final_string << @cd << "#{total_hours}"
    #games_played
      #intialize gamecounters
      city_counter = 0
      pictionary_counter = 0
      sniper_counter = 0
      scramble_counter = 0
      gender_game_hash = gender == :male ? @games_male : @games_female
    total_hours.times do
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
    final_string << @cd << "#{city_counter}" <<
                    @cd << "#{pictionary_counter}" <<
                    @cd << "#{scramble_counter}" <<
                    @cd << "#{sniper_counter}"
    #puts final_string
    output_file_handle.puts final_string
  end

  #close the file
  output_file_handle.close
  end #benchmark end
  puts "Time took to generate #{@lines} : #{time_took}"
end #end main_loop

#parallel runs to_generate lines which are > than 100k
if @num_of_processes > 1
  @num_of_processes.times do |count|
    tmp_file = "/tmp/analytics#{count}.data"
    ( @tmp_files ||= [] ) << tmp_file
    ( @pids ||= [] ) << Kernel.fork { main_loop(100000, tmp_file) }
  end
  @pids.each { |pid| Process.wait(pid) }
  @pids.clear
else
  main_loop(@lines, @output_file)
end