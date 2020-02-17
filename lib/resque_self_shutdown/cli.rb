require 'optparse'
require 'json'

module ResqueSelfShutdown
  class Cli
    def self.start!(argv)

      start_opts = {}

      # This has been simplified to just take a config file.  We could dispense with the optionparsing, but we'll keep it around for now
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: self_shutdown [options]"
        opts.separator ""
        opts.separator "Options:"
        opts.on("-c","--config-file PATH", String, "(required) JSON configuration file") do |s|
          start_opts[:config_file] = s
        end
        opts.on("-h", "--help", "Show this message") do
          puts opts
          exit
        end
      end

      parser.parse!(argv)
      begin
        raise(ArgumentError, "Must specify configuration file with -c or --config-file") unless start_opts[:config_file]
        runner = ResqueSelfShutdown::Runner.new(start_opts[:config_file])
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