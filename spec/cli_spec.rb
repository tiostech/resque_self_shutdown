require 'spec_helper'
require 'resque_self_shutdown/cli'
require 'tempfile'
require 'securerandom'

RSpec.describe ResqueSelfShutdown::Cli do

  describe 'bad inputs' do
    it 'complains if the config file is not specified' do
      expect {
        ResqueSelfShutdown::Cli.start!(['start'])
      }.to raise_error(ArgumentError, /Must specify configuration file/)
    end

    it 'complains if the config file cannot be parsed' do
      tmp = Tempfile.new('configfile')
      tmp << 'this"is"some-bad; json... ??? !#JKJKJ'
      tmp.flush

      expect {
        ResqueSelfShutdown::Cli.start!(["-c", tmp.path, 'start'])
      }.to raise_error(ArgumentError, /Problem parsing JSON/)
    end

    it 'complains if the config file does not exist' do
      expect {
        ResqueSelfShutdown::Cli.start!(["-c", "/path/to/non/existent/file.json", 'start'])
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
      argv = ['-c', config_file,'start']

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

    it 'daemonizes' do

      expect(ResqueSelfShutdown::Cli).to receive(:fork).twice.and_return(false)
      expect(Process).to receive(:setsid).and_return(true)

      expect($stdout).to receive(:reopen).with("/tmp/foo-out.log","a").and_return(true)
      expect($stderr).to receive(:reopen).with("/tmp/foo-err.log","a").and_return(true)

      expect(Dir).to receive(:chdir).with("/").and_return(true)

      loop_calls = 0
      allow_any_instance_of(ResqueSelfShutdown::Runner).to receive(:loop!) do |ss|
        loop_calls += 1
      end

      argv = ['-c', config_file,'-d','-o','/tmp/foo-out.log','-e','/tmp/foo-err.log','start']

      ResqueSelfShutdown::Cli.start!(argv)

      expect(loop_calls).to eq(1)
    end

  end




  describe "killing existing runners with stop" do
    it 'kills runners' do

      kill_commands = []
      allow(ResqueSelfShutdown::Cli).to receive(:command_output) do |cmd|
        if cmd == 'ps -A -o pid,command | grep "ResqueSelfShutdownMonitor"'
          puts "returning expected"
          [
              '1234 ResqueSelfShutdownMonitor::running',
              '2222 sh -c ps -A -o pid,command | grep "ResqueSelfShutdownMonitor"',
              '2224 grep ResqueSelfShutdownMonitor'
          ].join("\n")
        elsif cmd =~ /^kill /
          kill_commands << cmd
        else
          puts "Got unexpected Command: #{cmd}"
        end
      end

      ResqueSelfShutdown::Cli.start!(["stop"])

      expect(kill_commands).to eq(["kill -s QUIT 1234"])

    end
  end


end
