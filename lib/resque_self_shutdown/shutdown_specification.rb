module ResqueSelfShutdown
  # Self shutdown spec - looks like the following (all assume that no workers are currently running)
  #
  #   idlePreWork:800+10,idlePostWork:300+60 ==>
  #            If no jobs have completed, then shutdown after 800+rand(0..10) seconds since workers started
  #            If jobs have competed, then shut down after 300+rand(0..60) seconds since the last completion
  #
  #   0600-1200::idlePreWork:10800+300,idlePostWork:10800+300; idlePreWork:800+60,idlePostWork:300+60
  #       If current system (central) time is between 06:00 and 12:00 of current day...
  #            If no jobs have completed, then shutdown after 10800+rand(0..300) seconds since workers started
  #            If jobs have competed, then shut down after 10800+rand(0..300) seconds since the last completion
  #       Otherwise (all other hours)...
  #            If no jobs have completed, then shutdown after 800+rand(0..60) seconds since workers started
  #            If jobs have competed, then shut down after 300+rand(0..60) seconds since the last completion
  class ShutdownSpecification

    class TimeBlockSpecification < Struct.new(:time_start, :time_stop, :prework_base, :prework_rand, :postwork_base, :postwork_rand)
    end

    class DefaultSpecification < Struct.new(:prework_base, :prework_rand, :postwork_base, :postwork_rand)

    end

    def initialize(str)

      reset!
      parse_specification(str)
    end

    def self.valid?(str)
      begin
        inst = new(str)
        return true
      rescue => e
        return false
      end
    end

    def get_thresholds
      [
          get_threshold(:idle,:prework), # call this if no work has been done and we are measuring idle time since workers started
          get_threshold(:idle,:postwork), # call this if our idle time is based on work having been done.  Idle time since last complete
          get_threshold(:elapsed,:prework), # call this if our idle time is based on work having been done.  Idle time since last complete
      ]
    end

    def get_threshold(time_offset, type)

      raise StandardError, "Invalid type" unless [:prework, :postwork].include?(type)

      nowtime = Time.now
      seconds_since_day_start = nowtime.hour * 3600 + nowtime.min * 60 + nowtime.sec

      @time_ranges.each do |r|
        if seconds_since_day_start >= r.time_start && seconds_since_day_start <= r.time_stop
          return r.send((type.to_s + "_base").to_sym) + r.send((type.to_s + "_rand").to_sym)
        end
      end

      spec = case time_offset
             when :idle
               @default_spec
             when :elapsed
               @elapsed_spec
             else
               raise ArgumentError, "Invalid time_offset: '#{time_offset}'"
             end

      spec.nil? ? nil : spec.send((type.to_s + "_base").to_sym) + spec.send((type.to_s + "_rand").to_sym)
    end

    private

    def reset!
      @default_spec = nil
      @elapsed_spec = nil
      @time_ranges = []
    end


    def parse_specification(self_shutdown_spec)

      reset!

      if !self_shutdown_spec.nil?
        parts = self_shutdown_spec.split(/\s*;\s*/)

        parts.each do |part|
          if matches = /(idle|elapsed)PreWork:(\d+)\+(\d+)\,\1PostWork:(\d+)\+(\d+)$/.match(part)
            time_offset = matches[1].to_s
            prework_base = matches[2].to_i
            prework_rand = matches[3].to_i
            postwork_base = matches[4].to_i
            postwork_rand = matches[5].to_i

          else
            raise StandardError, "Cannot parse self shutdown spec.  Should have idlePreWork:123+10,idlePostWork:22+10 format but got #{self_shutdown_spec} "
          end

          if matches = /^(\d\d)(\d\d)\-(\d\d)(\d\d)::/.match(part)
            start_seconds = (matches[1].to_i * 3600 + matches[2].to_i * 60)
            stop_seconds  = (matches[3].to_i * 3600 + matches[4].to_i * 60)
            add_range!(start_seconds, stop_seconds, prework_base, prework_rand, postwork_base, postwork_rand)
          elsif time_offset == 'elapsed'
            set_elapsed!(prework_base, prework_rand, postwork_base, postwork_rand)
          else
            set_default!(prework_base, prework_rand, postwork_base, postwork_rand)
          end
        end
      end


    end

    def add_range!(start_seconds_of_day, stop_seconds_of_day, prework_idle_base, prework_idle_rand, postwork_idle_base, post_work_idle_rand)
      @time_ranges << TimeBlockSpecification.new(start_seconds_of_day, stop_seconds_of_day, prework_idle_base, prework_idle_rand, postwork_idle_base, post_work_idle_rand)
    end

    def set_elapsed!(prework_idle_base, prework_idle_rand, postwork_idle_base, post_work_idle_rand)
      @elapsed_spec = DefaultSpecification.new(prework_idle_base, prework_idle_rand, postwork_idle_base, post_work_idle_rand)
    end

    def set_default!(prework_idle_base, prework_idle_rand, postwork_idle_base, post_work_idle_rand)
      @default_spec = DefaultSpecification.new(prework_idle_base, prework_idle_rand, postwork_idle_base, post_work_idle_rand)
    end
  end

end