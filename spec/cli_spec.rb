require 'spec_helper'
require 'resque_self_shutdown/cli'

RSpec.describe ResqueSelfShutdown::Cli do

  describe 'bad inputs' do
    it 'complains if the config file is not specified' do
      expect {
        ResqueSelfShutdown::Cli.start!([])
      }.to raise_error(ArgumentError, /Must specify configuration file/)
    end

    it 'complains if the config file does not exist' do
      expect {
        ResqueSelfShutdown::Cli.start!(["-c", "/path/to/non/existent/file.json"])
      }.to raise_error(ArgumentError, /Configuration file .* does not exist/)
    end
  end

  describe 'config file arguments' do
    let(:temp_dir) {
      tmp = "/tmp/foo-#{SecureRandom.uuid}"
      puts "Writing #{tmp}"
      FileUtils.mkdir_p(tmp)
      tmp
    }

    let(:config_file) {
      cfile = "#{temp_dir}/config.json"
      File.open(cfile, 'wb') do |f|
        f.write(JSON.pretty_generate({
            :stop_runners_script => "/usr/bin/env",
            :process_running_regex => 'foo',
            :process_working_regex => 'bar',
            :last_complete_file => "#{temp_dir}/latestJobCompleteUTC.txt",
            :last_error_file => "#{temp_dir}/latestJobErrorUTC.txt",
            :workers_start_file => "#{temp_dir}/workersStartedUTC.txt",
            :self_shutdown_specification => "idlePreWork:10800+300,idlePostWork:900+600",
            :sleep_time => 30,
            :sleep_time_during_shutdown => 10
        }))
      end
      cfile
    }

    it 'processes arguments' do
      argv = ['-c', config_file]

      loop_calls = 0
      allow_any_instance_of(ResqueSelfShutdown::Runner).to receive(:loop!) do |ss|

        loop_calls += 1

        # verify options passing
        expect(ss.shutdown_spec.to_s).to eq('idlePreWork:10800+300,idlePostWork:900+600')
        expect(ss.process_running_regex).to eq('foo')
        expect(ss.process_working_regex).to eq('bar')
        expect(ss.stop_runners_script).to eq('/usr/bin/env')
        expect(ss.last_complete_file).to eq("#{temp_dir}/latestJobCompleteUTC.txt")
        expect(ss.last_error_file).to eq("#{temp_dir}/latestJobErrorUTC.txt")
        expect(ss.workers_start_file).to eq("#{temp_dir}/workersStartedUTC.txt")

      end

      ResqueSelfShutdown::Cli.start!(argv)

      expect(loop_calls).to eq(1)
    end
  end


end
