#!/usr/local/bin/ruby

#model sampling

require 'distribution'
require 'trollop'
require 'csv'

include Distribution
module Distribution::Dirac
   def self.rng(rate)
      interval = 1.0/rate
      lambda{ return interval }
   end
end



Event = Struct.new(:start, :finish, :detected, :detect_time, :delay)


$time = 0


event_interval = 1
event_length = 1



opts =Trollop.options do
   opt :interval, "Sample interval", default: 10.0
   opt :sample_dist, "Sample distribution", default: "Exponential"
   opt :events, "Event interval", default: 10.0
   opt :event_dist, "Event Distribution", default: "Exponential"
   opt :length, "Event length", default: 5.0
   opt :length_dist, "Event length Distribution", default: "Exponential"
   opt :run, "Run events", default: 1000000
   opt :csv, "CSV file output", default: false
end

class Sampler
   def initialize(opts)
      @opts = opts

      @event_generator = Module.const_get(opts[:event_dist]).rng(1.0/opts[:events])
      @length_generator = Module.const_get(opts[:length_dist]).rng(1.0/opts[:length])
      @sample_generator =Module.const_get(opts[:sample_dist]).rng(1.0/opts[:interval])
      @run_length =opts[:run]

      @detected = false

      @next_event_on = 0.0
      @next_event_off = 0.0
      @tally = 0
      @samples = 0
      @events = []

   end

   def create_event
      @next_event_on = @next_event_off + @event_generator.call
      @next_event_off = @next_event_on + @length_generator.call
      @tally += 1
      @detected = false
   end

   def run
      time = 0.0

      while @tally < @run_length
         # create the next event, bearing in mind that it could start
         # and end before the next sample
         begin
            create_event
            if  @next_event_off < time
               # if the event finishes before the current time, we have missed it
               # so record the miss
               @events << Event.new(@next_event_on, @next_event_off, false, time, nil)
            end
         end until @next_event_off > time

         while time < @next_event_off
            time += @sample_generator.call
            @samples += 1
            if !@detected && time >= @next_event_on
               if time <= @next_event_off
                  #event detected - record
                  @detected = true
                  @events << Event.new(@next_event_on, @next_event_off, @detected, time, time - @next_event_on)
               else
                  #event missed - record
                  @events << Event.new(@next_event_on, @next_event_off, @detected, time, nil)
               end
            end
         end

      end
   end

   def output
      filename = [   @opts[:sample_dist].downcase,
                     @opts[:interval],
                     @opts[:event_dist].downcase,
                     @opts[:events],
                     @opts[:length_dist].downcase,
                     @opts[:length] ].join('_')
      CSV.open(filename, 'wb') do |csv|
         csv << Event.members
         @events.each do |e|
            csv << e.to_a
         end
      end
   end

   def stats
      puts "S Dist     = #{@opts[:sample_dist]}"
      puts "S Interval = #{@opts[:interval]}"
      puts "E Dist     = #{@opts[:event_dist]}"
      puts "E interval = #{@opts[:events]}"
      puts "E L Dist   = #{@opts[:length_dist]}"
      puts "E length   = #{@opts[:length]}"
      puts "Samples    = #{@samples}"
      puts "Tally      = #{@tally}"
      detected = @events.count{|e| e.detected}
      puts "Detected   = #{detected}"
      puts "Tally %    = #{detected * 100.0 / @tally}"
      puts "Sample %   = #{detected * 100.0 / @samples}"
      puts "Delay      = #{@events.inject(0){|s,e| s += (e.delay || 0); s} / detected }"
   end

end

#main routine
s = Sampler.new(opts)
s.run
s.output if opts[:csv]
s.stats
