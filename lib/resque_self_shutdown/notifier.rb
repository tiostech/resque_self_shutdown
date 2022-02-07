require 'logger'
require 'time'

module ResqueSelfShutdown
  class Notifier

    attr_reader :logger

    include ResqueSelfShutdown::ConfigReader


    # Parameters
    # config_file: [String] a filename for a JSON file that has the parameters below.
    #       "last_complete_file": [String] path to file that will be present when a worker finishes doing work.  Contents should be timestamp: %Y-%m-%d %H:%M:%S %Z
    #       "last_error_file": [String] path to file that will be present when there is an error
    #       "workers_start_file": [String] path to file that will be present when workers start doing work.  Contents should be timestamp: %Y-%m-%d %H:%M:%S %Z
    #
    # These config parameters are a subset of the Runner configurations.
    # Of those parameters, we are only going to use last_complete_file, last_error_file, and workers_start_file here.
    def initialize(config_file)

      parse_config(config_file)

      raise ArgumentError, "Must specify last_complete_file" unless last_complete_file
      raise ArgumentError, "Must specify last_error_file" unless last_error_file
      raise ArgumentError, "Must specify workers_start_file" unless workers_start_file

      FileUtils.mkdir_p File.dirname(last_complete_file)
      FileUtils.mkdir_p File.dirname(last_error_file)
      FileUtils.mkdir_p File.dirname(workers_start_file)

      @logger = Logger.new(STDOUT)
      @logger.level = Logger::DEBUG
    end

    def clear!
      [last_complete_file, last_error_file, workers_start_file].each do |f|
        File.delete(f) if File.exists?(f)
      end
    end

    def notify_error!
      _write_notification(last_error_file)
    end

    def notify_complete!
      _write_notification(last_complete_file)
    end

    def notify_worker_start!
      _write_notification(workers_start_file)
    end

    private

    def _write_notification(filename)
      File.open(filename,'wb') {|f| f.write(_format_time) }
    end

    def _format_time
      Time.now.utc.strftime('%Y-%m-%d %H:%M:%S %Z')
    end

  end
end
