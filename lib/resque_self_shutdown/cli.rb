require 'optparse'
require 'json'

module ResqueSelfShutdown
  class Cli
    def self.start!(argv)

      start_opts = {}

      # This has been simplified to just take a config file.  We could dispense with the optionparsing, but we'll keep it around for now
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: self_shutdown [options] COMMAND"
        opts.separator ""
        opts.separator "COMMAND is one of start or stop"
        opts.separator "Options:"
        opts.on("-c","--config-file PATH", String, "(required) JSON configuration file") do |s|
          start_opts[:config_file] = s
        end
        opts.on("-d", "Run as daemon") do
          start_opts[:daemonize] = true
        end
        opts.on("-o","--output-log PATH", String, "Output logging to this file - only if running as daemon") do |s|
          start_opts[:output_log] = s
        end
        opts.on("-e","--error-log PATH", String, "Error logging to this file - only if running as daemon") do |s|
          start_opts[:error_log] = s
        end

        opts.on("-h", "--help", "Show this message") do
          puts opts
          exit
        end
      end

      parser.parse!(argv)
      command = argv[0]

      raise(ArgumentError, "Command must be specified: start or stop") unless ['start','stop'].include?(command)

      begin
        case command
        when 'start'
          $0 = "ResqueSelfShutdownMonitor::running"
          raise(ArgumentError, "Must specify configuration file with -c or --config-file") unless start_opts[:config_file]
          runner = ResqueSelfShutdown::Runner.new(start_opts[:config_file])
          deamonize!(start_opts) if start_opts[:daemonize]
          runner.loop!
        when 'stop'
          kill_shutdown_monitors
        end

      rescue ArgumentError => e
        puts "Error with parameters!: #{e.message}"
        puts parser.help
        raise e
      rescue => other
        raise other
      end

    end

    private

    def self.deamonize!(start_opts)
      # https://www.honeybadger.io/blog/unix-daemons-in-ruby/

      exit if fork
      Process.setsid
      exit if fork

      if start_opts[:output_log]
        FileUtils.mkdir_p(File.dirname(start_opts[:output_log]))
        $stdout.reopen start_opts[:output_log], 'a'
        $stdout.sync = true
      else
        $stdout.reopen '/dev/null', 'a'
      end

      if start_opts[:error_log]
        FileUtils.mkdir_p(File.dirname(start_opts[:error_log]))
        $stderr.reopen start_opts[:error_log], 'a'
        $stderr.sync = true
      else
        $stderr.reopen '/dev/null', 'a'
      end

      Dir.chdir("/")
    end

    def self.get_self_shutdown_pids
      pids = []
      command_output('ps -A -o pid,command | grep "ResqueSelfShutdownMonitor"').split("\n").each do |psline|
        if psline.include?("ResqueSelfShutdownMonitor::running") && !psline.include?("grep")
          pid = psline.split(' ')[0]
          puts "Found PID line [#{pid}]: #{psline.chomp}"
          pids << pid
        end
      end
      return pids
    end

    def self.kill_shutdown_monitors

      pids = get_self_shutdown_pids
      if pids.empty?
        puts "No self-shutdown monitor to kill..."
      else
        syscmd = "kill -s QUIT #{pids.uniq.join(' ')}"
        command_output(syscmd)
        puts "Done killing self shutdown monitor"
      end
    end


    def self.command_output(cmd)
      `#{cmd}`
    end

  end
end