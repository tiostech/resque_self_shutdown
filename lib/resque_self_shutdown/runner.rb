require 'logger'
require 'time'

module ResqueSelfShutdown
  class Runner

    attr_reader :logger,:shutdown_spec

    include ResqueSelfShutdown::ConfigReader

    # Parameters
    # config_file: [String] a filename for a JSON file that has the parameters below.
    #       "stop_runners_script": [String] the script to call to stop runners
    #       "process_running_regex": [String] grep string to use for searching for Resque processes running
    #       "process_working_regex": [String] grep string to use for searching for Resque workers doing work
    #       "last_complete_file": [String] path to file that will be present when a worker finishes doing work.  Contents should be timestamp: %Y-%m-%d %H:%M:%S %Z
    #       "last_error_file": [String] path to file that will be present when there is an error
    #       "workers_start_file": [String] path to file that will be present when workers start doing work.  Contents should be timestamp: %Y-%m-%d %H:%M:%S %Z
    #       "sleep_time": [int/String] number of seconds to sleep between checks
    #       "sleep_time_during_shutdown": [int/String] number of seconds to sleep between checks, after stopping workers and waiting for them to be done and then shutting down
    #       "self_shutdown_specification": [String] shutdown specification
    def initialize(config_file)

      parse_config(config_file)

      raise ArgumentError, "Must specify stop_runners_script" unless stop_runners_script
      raise ArgumentError, "Must specify last_complete_file" unless last_complete_file
      raise ArgumentError, "Must specify last_error_file" unless last_error_file
      raise ArgumentError, "Must specify workers_start_file" unless workers_start_file
      raise ArgumentError, "Must specify non-empty self_shutdown_specification" if (shutdown_spec_str.nil? || shutdown_spec_str == '')

      # this will raise an error if the specification fails to parse
      @shutdown_spec = ShutdownSpecification.new(shutdown_spec_str)

      @logger = Logger.new(STDOUT)
      @logger.level = Logger::DEBUG
    end

    def time_thresholds
      shutdown_spec.get_thresholds
    end

    def loop!

      loop do
        # we will check against both of these.  We care first about time since latest completion
        time_check = time_since_latest_completion() || time_since_workers_start()

        prework_time_check = time_since_workers_start()
        postwork_time_check = time_since_latest_completion()


        if prework_time_check.nil? && postwork_time_check.nil?

          logger.info "No time check available yet.  Probably workers have not started yet"

        else

          prework_threshold, postwork_treshold, elapsed_threshold = time_thresholds

          num_working = num_working_processes

          logger.info "check: NumWorkers: #{num_working} ... PostWork: #{postwork_time_check || 'NA'} >= #{postwork_treshold}; PreWork: #{prework_time_check} >= #{prework_threshold}; Elapsed: #{prework_time_check || 'NA'} >= #{elapsed_threshold};"

          if num_working == 0 && ((!postwork_time_check.nil? && !postwork_treshold.nil? && postwork_time_check >= postwork_treshold) ||
              (postwork_time_check.nil? && !prework_time_check.nil? && !prework_threshold.nil? && prework_time_check >= prework_threshold) ||
              (!prework_time_check.nil? && !elapsed_threshold.nil? && prework_time_check >= elapsed_threshold))

            # Stop the workers
            logger.info "Stopping workers with #{stop_runners_script}: staleness check: PostWork: #{postwork_time_check || 'NA'} >= #{postwork_treshold}; PreWork: #{prework_time_check} >= #{prework_threshold}"
            command_output("#{stop_runners_script}")

            logger.info "Waiting for processes to be done"
            while(num_running_processes > 0)
              sleep(sleep_time_during_shutdown)
            end

            # We used to keep the servers up indefinitely if there was an error, but that causes more problems than benefits
            if has_errors?
              logger.info "Errors were present -- but permitting shutdown"
              command_output("echo errors-present-but-continuing-with-shutdown") # used only for testing
            end

            logger.info "Initiating Shutdown...."
            command_output("sudo shutdown -h now")

            break
          end

        end

        sleep(sleep_time)
      end

    end

    private

    def command_output(cmd)
      `#{cmd}`
    end


    def num_running_processes
      command_output("pgrep -f -c '#{process_running_regex}'").lines.first.to_i
    end

    def num_working_processes
      command_output("pgrep -f -c '#{process_working_regex}'").lines.first.to_i
    end


    def time_since_timestamp_file(file_path, mode = :timestamp_file)
      timestamp_time = case mode
                       when :timestamp_file

                         timestamp = File.read(file_path).chomp rescue nil
                         if timestamp.nil?
                           logger.warn("Could not read #{file_path}")
                           nil
                         else
                           begin
                             Time.strptime(timestamp, '%Y-%m-%d %H:%M:%S %Z').utc
                           rescue => e
                             logger.warn("Could not parse timestamp #{timestamp} from #{file_path}: #{e.message}")
                             nil
                           end
                         end
                       when :mtime
                         begin
                           File.mtime(file_path)
                         rescue => e
                           logger.warn("Could not get mtime from #{file_path}: #{e.message}")
                           nil
                         end
                       else
                         nil
                       end
      unless timestamp_time.nil?
        (Time.now.utc - timestamp_time).to_i
      end
    end

    def time_since_latest_completion
      time_since_timestamp_file(last_complete_file)
    end

    def time_since_workers_start
      time_since_timestamp_file(workers_start_file) || time_since_timestamp_file(server_start_file, :mtime)
    end

    def has_errors?
      File.exists?(last_error_file)
    end


  end
end
