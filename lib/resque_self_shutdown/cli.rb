require 'optparse'
require 'json'

module ResqueSelfShutdown
  class Cli
    def self.start!(argv)

      start_opts = {}

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: self_shutdown [options] \"SPEC\""
        opts.separator ""
        opts.separator "Options:"
        opts.on("--config-file PATH", String, "JSON configuration file") do |s|
          start_opts[:config_file] = s
        end
        opts.on("--stop-runners-script PATH", String, "script to call to stop workers") do |s|
          start_opts[:stop_runners_script] = s
        end
        opts.on("--process-running-regex REGEX", String, "regular expression search for process-running check") do |s|
          start_opts[:process_running_regex] = s
        end
        opts.on("--process-working-regex REGEX", String, "regular expression search for workers-working check") do |s|
          start_opts[:process_working_regex] = s
        end
        opts.on("--last-complete-file PATH", String, "path to text file that notifies last job completion. Contents of file expected to be timestamp: %Y-%m-%d %H:%M:%S %Z ") do |s|
          start_opts[:last_complete_file] = s
        end
        opts.on("--last-error-file PATH", String, "path to text file that notifies last error detection. Contents of file expected to be timestamp: %Y-%m-%d %H:%M:%S %Z ") do |s|
          start_opts[:last_error_file] = s
        end
        opts.on("--workers-start-file PATH", String, "path to text file that notifies last worker start. Contents of file expected to be timestamp: %Y-%m-%d %H:%M:%S %Z ") do |s|
          start_opts[:workers_start_file] = s
        end
        opts.on("--sleep-time SECONDS", Integer, "number of seconds to sleep between checks") do |i|
          start_opts[:sleep_time] = i
        end
        opts.on("--sleep-time-during-shutdown SECONDS", Integer, "number of seconds to sleep between checks, after stopping workers and waiting for them to be done and then shutting down") do |i|
          start_opts[:sleep_time_during_shutdown] = i
        end
        opts.on("-h", "--help", "Show this message") do
          puts opts
          exit
        end
      end

      parser.parse!(argv)
      self_shutdown_specification = argv[0]

      start_opts.merge!(:self_shutdown_specification => self_shutdown_specification)

      begin
        runner = ResqueSelfShutdown::Runner.new(start_opts)

        puts "Starting Self-Shutdown with options:"
        puts JSON.pretty_generate(start_opts)

      rescue ArgumentError => e
        puts "Error with parameters!: #{e.message}"
        puts parser.help
        raise e
      rescue => other
        raise other
      end

      runner.loop!
    end
  end
end