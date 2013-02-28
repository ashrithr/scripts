#!/usr/bin/env ruby
# ---
# => Script to generate random data required for data analytics
# ---
require 'rubygems'
require 'fileutils'

# => PHASE 1
# Generate data to a file
# cid<=>gender<=>age<=>country<=>num_of_friends
# cid -> can be from 1000 onwards.
# gender -> should be taken from array @gender randomly
# country -> should be taken from array @countries randomly
#
# => PHASE 2
# Lifetime(in days)<=>Gamesplayed(1,2,3,4)
# if lifetime is > then user tend to play more games
# also if user is female then games played will be

#Potential Gem Matches
#https://github.com/stympy/faker -> generates fake data
#https://github.com/muffinista/namey -> generates names using US census db
#https://github.com/alexgutteridge/rsruby -> Ruby's full access to full R
#                                            statistical programming env.
#https://github.com/xuanxu/croupier -> generates random samples of numbers
#                                      with specific probability distributions.

#Globals
@lines = 100                              #No. of lines to generate
@output_file = "/tmp/analytics.data"      #Output file
@cd = ","                                 #column delimeter
@ld = "\n"                                #line delimeter
@cid_start = 1000                         #Customer id start int
@gender = ["male", "female"]              #Gender array
@gender_with_probability = {              #Gender hash with probability
  :male   => 70,
  :female => 30
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

# => MAIN LOOP
@counter = @cid_start + @lines
#Check and output create file
FileUtils.touch(@output_file) unless File.exists? @output_file

#open up the file for writing
output_file = File.open(@output_file, "w")

#header
output_file.puts "cid#{@cd}gender#{@cd}age#{@cd}country#{@cd}frined_count#{@cd}\
lifetime(days)#{@cd}citygame_played#{@cd}pictionarygame_played#{@cd}\
scramblegame_played#{@cd}snipergame_played"

#TODO: Build string at end vs build string as you go
(@cid_start..@counter).each do |cid|
  final_string = ""
  final_string << "#{cid}"
  #gender
  #gender = @gender[rand(@gender.size)]                     #Regular case
  gender = choose_weighted(@gender_with_probability)
  final_string << @cd << "#{gender}"                        #weighted
  #age
  #age = (18 + rand(32))                                    #age between 18-50
  final_string << @cd << "#{choose_weighted(@age_with_probability)}"  #weighted
  #country
  final_string << @cd << @countries[rand(@countries.size)]
  #friends_count
  final_string<< @cd << "#{rand(100)}"
  #total_hours_played_in_days
  total_hours = rand(1000)
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
    else :sniper
      sniper_counter += 1
    end
  end
  final_string << @cd << "#{city_counter}" << @cd << "#{pictionary_counter}" <<
                  @cd << "#{scramble_counter}" << @cd << "#{sniper_counter}"
  puts final_string
  output_file.puts final_string
end

#close the file
output_file.close

#choose_weighted example
# gender = { :male => 70, :female => 70 }

# males = 0
# females = 0
# 1000.times { |id|
#   return_value = choose_weighted(gender)
#   return_value == :male ? males += 1 : females +=1
# }
# puts "males: #{males}/1000"
# puts "females: #{females}/1000"

# class Array
# # => Add/Override methods to Array class
#   def sum
#     # => Calculates the sum of elemets in an array
#     inject( nil ) { |sum,x| sum ? sum+x : x }
#   end

#   def mean
#     # => Calculates mean of elements in array
#     sum / size
#   end

#   def probability(spread = 2)
#   # => Returns probability for array elements
#   # NOTE: The higher the spread, the more even the distribution is going to be
#     z = 1.0
#     collect {|x| z = z / spread}
#   end

#   def weighted_random_index(probability_array = probability(2))
#     # => Returns weighted random index
#     size.times do |x|
#       #p "rand is #{rand} and #{probability_array[0..x].sum}"
#       return x if rand < probability_array[0..x].sum
#     end
#     return 0
#   end

#   def get_weighted_random_item(probability_array = probability(2))
#     # => Returns value matching its weighted_index from actual array
#     self[weighted_random_index(probability_array)]
#   end

#   def get_weighted_random_indexes(num_items, p = probability(2))
#     # => Returns selected indexes
#     res = []
#     escape = 1000
#     while res.size < num_items and escape > 0
#       escape -= 1
#       tmp = weighted_random_index(p)
#       res << tmp unless res.include?(tmp)
#     end
#     return res.sort
#   end
# end

# def weighted_random_index_example
#   arr = ['citygame', 'sniper', 'pictionary', 'game4']
#   puts "Sample array = [#{arr.join(",")}]"
#   p = [0.5,0.25, 0.15, 0.10]
#   puts "Probability that each will show up [#{p.join(', ')}]"
#   puts "1000 runs..."
#   res = Array.new(arr.size).fill(0)
#   1000.times do |t|
#     res[arr.weighted_random_index(p)] += 1
#   end
#   res2 = res.collect {|x| (x/1000.0) * 100}
#   puts "Results:"
#   4.times do |t|
#     puts "    #{arr[t]}: #{res2[t]}%"
#   end

#   puts ""
#   puts "You can also use more spread out probability arrays"
#   p = arr.probability(3)
#   puts "Probability that each will show up with a spread of 3 [#{p.join(', ')}]"
#   puts "1000 runs..."
#   res = Array.new(arr.size).fill(0)
#   1000.times do |t|
#     res[arr.weighted_random_index(p)] += 1
#   end
#   res2 = res.collect {|x| (x/1000.0) * 100}
#   puts "Results:"
#   4.times do |t|
#     puts "    #{arr[t]}: #{res2[t]}%"
#   end

#   puts ""
#   puts "You can also just get selected indexes"
#   puts "arr.get_weighted_random_indexes(3,p) = [#{arr.get_weighted_random_indexes(3,p).join(', ')}]"

#   puts "The probability spread will depend on the number of items in your array - for an array of 4 it looks like this:"
#   8.times do |t|
#     puts "  probability(#{t+2}):  [#{arr.probability(t+2).collect {|x| sprintf('%0.5f',x)}.join(', ')}]"
#   end
#   return nil
# end

#Run this script if run as a file
if __FILE__ == $0
  #arr = ['citygame', 'sniper', 'pictionary', 'game4']
  #p arr.probability(2)
  #p arr.probability(4)
  # 10.times do |i|
  #   puts arr.get_weighted_random_item([0.5, 0.25, 0.15, 0.10])
  # end
  #weighted_random_index_example
end