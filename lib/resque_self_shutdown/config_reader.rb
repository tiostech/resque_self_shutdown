
module ResqueSelfShutdown
  module ConfigReader

    def self.included(klass)
      klass.class_eval do

        attr_reader :stop_runners_script,
            :process_running_regex, :process_working_regex,
            :last_complete_file, :last_error_file,:workers_start_file, :server_start_file,
            :sleep_time, :sleep_time_during_shutdown, :shutdown_spec_str

        include InstanceMethods
      end
    end

    module InstanceMethods

      def parse_config(config_file)

        raise ArgumentError, "Configuration file #{config_file} does not exist" unless File.exists?(config_file)

        begin
          config_file_opts = JSON.parse(File.read(config_file))
        rescue => e
          raise ArgumentError, "Problem parsing JSON configuration file #{config_file}: #{e.message}"
        end
        config_file_opts

        @stop_runners_script   = config_file_opts['stop_runners_script']
        @process_running_regex = config_file_opts['process_running_regex']
        @process_working_regex = config_file_opts['process_working_regex']
        @last_complete_file    = config_file_opts['last_complete_file']
        @last_error_file       = config_file_opts['last_error_file']
        @workers_start_file    = config_file_opts['workers_start_file']
        @server_start_file     = config_file_opts['server_start_file']
        @shutdown_spec_str     = config_file_opts['self_shutdown_specification']
        @sleep_time            = (config_file_opts['sleep_time'] || 30).to_i
        @sleep_time_during_shutdown = (config_file_opts['sleep_time_during_shutdown'] || 10)
      end
    end

  end
end