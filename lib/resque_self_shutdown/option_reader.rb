module ResqueSelfShutdown
  class OptionReader

    attr_reader :stop_runners_script,
        :process_running_regex, :process_working_regex,
        :last_complete_file, :last_error_file,:workers_start_file,
        :sleep_time, :sleep_time_during_shutdown

    # Options:
    #   :config_file: [String] a filename for a JSON file that has the parameters below.
    #   :stop_runners_script : [String] the script to call to stop runners
    #   :process_running_regex : [String] grep string to use for searching for Resque processes running
    #   :process_working_regex : [String] grep string to use for searching for Resque workers doing work
    #   :last_complete_file: [String] path to file that will be present when a worker finishes doing work.  Contents should be timestamp: %Y-%m-%d %H:%M:%S %Z
    #   :last_error_file: [String] path to file that will be present when there is an error
    #   :workers_start_file: [String] path to file that will be present when workers start doing work.  Contents should be timestamp: %Y-%m-%d %H:%M:%S %Z
    #   :sleep_time: [int/String] number of seconds to sleep between checks
    #   :sleep_time_during_shutdown: [int/String] number of seconds to sleep between checks, after stopping workers and waiting for them to be done and then shutting down
    def initialize(options={})

      config_file_opts = {}
      if options[:config_file]
        unless File.exists?(options[:config_file])
          raise ArgumentError, "Configuration file #{options[:config_file]} does not exist"
        end
        config_file_opts = JSON.parse(File.read(options[:config_file]))
      end


      @stop_runners_script   = (options[:stop_runners_script] || config_file_opts['stop_runners_script'])
      @process_running_regex = (options[:process_running_regex] || config_file_opts['process_running_regex'])
      @process_working_regex = (options[:process_working_regex] || config_file_opts['process_working_regex'])
      @last_complete_file    = (options[:last_complete_file] || config_file_opts['last_complete_file'])
      @last_error_file       = (options[:last_error_file] || config_file_opts['last_error_file'])
      @workers_start_file    = (options[:workers_start_file] || config_file_opts['workers_start_file'])
      @shutdown_spec_str     = (options[:self_shutdown_specification] || config_file_opts['self_shutdown_specification'])
      @sleep_time            = (options[:sleep_time] || config_file_opts['sleep_time'] || 30).to_i
      @sleep_time_during_shutdown = (options[:sleep_time_during_shutdown] || config_file_opts['sleep_time_during_shutdown'] || 10).to_i

    end
  end
end
