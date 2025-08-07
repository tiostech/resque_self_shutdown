require 'spec_helper'
require 'date'
require 'securerandom'

RSpec.describe ResqueSelfShutdown do


  let(:shutdown_spec) { 'idlePreWork:10800+300,idlePostWork:900+600' }
  let(:process_running_regex) { '^resque-'}
  let(:process_working_regex) { '^resque-.*: Processing' }
  let(:stop_runners_script)   { '/usr/bin/env' }  # just a placeholder script
  let(:last_complete_file)    { '/tmp/latestJobCompleteUTC.txt' }
  let(:last_error_file)       { '/tmp/latestJobErrorUTC.txt' }
  let(:workers_start_file)    { '/tmp/workersStartedUTC.txt' }
  let(:server_start_file)     { '/tmp/READY.txt' }
  let(:instance_id) { 'i-123456789'}
  let(:env_tios_aws_url) { "https://some-management.tioscapital.com"}
  let(:env_self_shutdown_tiosaws_endpoint) { "instances/self_shutdown_terminate" }

  let(:sleep_time_during_shutdown) { 10 }
  let(:sleep_time) { 30 }

  let(:system_calls) { [] }
  let(:sleep_times) { [] }

  let(:temp_dir) {
    tmp = "/tmp/foo-#{SecureRandom.uuid}"
    puts "Writing #{tmp}"
    FileUtils.mkdir_p(tmp)
    tmp
  }

  let(:config_file) {
    File.open("#{temp_dir}/config.json", 'wb') do |f|
      f.write(JSON.pretty_generate({
          :stop_runners_script => stop_runners_script,
          :process_running_regex => process_running_regex,
          :process_working_regex => process_working_regex,
          :last_complete_file => last_complete_file,
          :last_error_file => last_error_file,
          :server_start_file => server_start_file,
          :workers_start_file => workers_start_file,
          :self_shutdown_specification => shutdown_spec,
          :sleep_time => sleep_time,
          :sleep_time_during_shutdown => sleep_time_during_shutdown
      }))
    end
    "#{temp_dir}/config.json"
  }


  let(:shutdown) {
    ResqueSelfShutdown::Runner.new(config_file)
  }

  after(:each) do
    FileUtils.rm_rf(temp_dir)
  end

  
  shared_examples 'shutdown verifications' do

    before(:each) do
      File.delete(workers_start_file) rescue nil
      File.delete(last_complete_file) rescue nil
      File.delete(last_error_file) rescue nil
      File.delete(server_start_file) rescue nil

      @num_running_processes = 1
      @num_working_processes = 1
    
      allow(ENV).to receive(:[]).with('TIOS_AWS_URL').and_return(env_tios_aws_url)
      allow(ENV).to receive(:[]).with('TAG_SELF_SHUTDOWN_TIOSAWS_ENDPOINT').and_return(env_self_shutdown_tiosaws_endpoint)
      allow(ENV).to receive(:[]).with('SHUTDOWN_NOTIFY_FILE').and_return(nil)
    
      allow_any_instance_of(ResqueSelfShutdown::Runner).to receive(:get_instance_id).and_return(instance_id) # we stub here to block the extra system call
    
      allow_any_instance_of(ResqueSelfShutdown::Runner).to receive(:command_output) do |obj,cmd|

        system_calls << cmd

        case(cmd)
        when "pgrep -fcx '#{process_running_regex}'"

          puts "running: #{@num_running_processes}"
          @num_running_processes.to_s
        when "pgrep -fcx '#{process_working_regex}'"
          puts "working: #{@num_working_processes}"
          @num_working_processes.to_s

        when "echo errors-present-but-continuing-with-shutdown"
          puts "detected errors but continuing on"
          "errors-present-but-continuing-with-shutdown"

        when "curl -s http://169.254.169.254/latest/meta-data/instance-id"
          instance_id
        
        
        when "curl -s -d \"instance_id=#{instance_id}\" -X POST #{env_tios_aws_url}/#{env_self_shutdown_tiosaws_endpoint}"
          "Going down via #{cmd}"
          raise StandardError, "ShutDown Via: #{cmd}"
        when "sudo shutdown -h now"
          "Going down"
          raise StandardError, "ShutDown Via: #{cmd}"  # to help with testing, do this
        end
      end
    end

    
    describe "general flows" do

      let(:shutdown_spec) { 'idlePreWork:10800+300,idlePostWork:730+10' }

      before(:each) do
        ## We emulate a stop-workers that stops after a number of sleeps
        allow(shutdown).to receive(:sleep) do |stime|
          puts "inside sleep"
          sleep_times << stime
          # after a couple sleeps, we are down to 0 working
          if sleep_times.select {|s| s == sleep_time}.count >= 2
            puts "Seting processes to 1,0"
            @num_running_processes = 1
            @num_working_processes = 0
          end
          # after a couple of sleeps after post-stop-workers, we are down to 0 running, 0 working
          if sleep_times.select {|s| s == sleep_time_during_shutdown }.count >= 2
            puts "setting processes to 0,0"
            @num_running_processes = 0
            @num_working_processes = 0
          end
        end
      end

      it 'should never shut down if something is still working' do
        # bypass the process changing before block above.
        shutdown2 = ResqueSelfShutdown::Runner.new(config_file)
        sleeps2 = []
        @num_running_processes = 1
        @num_working_processes = 1
        
        # Apply the same mocking to shutdown2 instance
        allow(shutdown2).to receive(:get_instance_id).and_return(instance_id) if defined?(instance_id)
        
        allow(shutdown2).to receive(:command_output) do |cmd|
          system_calls << cmd
          
          case(cmd)
          when "pgrep -fcx '#{process_running_regex}'"
            @num_running_processes.to_s
          when "pgrep -fcx '#{process_working_regex}'"
            @num_working_processes.to_s
          when "echo errors-present-but-continuing-with-shutdown"
            "errors-present-but-continuing-with-shutdown"
          when "curl -s http://169.254.169.254/latest/meta-data/instance-id"
            instance_id
          when "curl -s -d \"instance_id=#{instance_id}\" -X POST #{env_tios_aws_url}/#{env_self_shutdown_tiosaws_endpoint}"
            "Going down via #{cmd}"
            raise StandardError, "ShutDown Via: #{cmd}"
          when "sudo shutdown -h now"
            "Going down"
            raise StandardError, "ShutDown Via: #{cmd}"  # to help with testing, do this
          end
        end
        
        allow(shutdown2).to receive(:sleep) do |stime|
          sleeps2 << stime
          if stime == sleep_time_during_shutdown
            @num_running_processes = 0
            @num_working_processes = 0
          else
            raise StandardError, "No sleep!"
          end
        end

        start_seconds_ago = 12000
        pretend_now_is(DateTime.parse('2018-07-25 11:16:00 EDT')) do
          File.delete(last_complete_file) rescue nil
          File.open(workers_start_file, 'wb') {|f| f.puts (Time.now.utc - start_seconds_ago).strftime('%Y-%m-%d %H:%M:%S %Z') }

          # this would normally sleep because something is actually still running - but we block normal sleeping above -
          # to prove that the sleeping and looping continues when something is working
          expect {
            shutdown2.loop!
          }.to raise_error(StandardError, /No sleep/)

          # suppose nothign is working.  It doesn't finish, but dies for some reason.  Now it's stale the prework should trigger shutdown
          @num_working_processes = 0
          if expected_shutdown_cmd.nil?
            expect {
              shutdown2.loop!
            }.not_to raise_error
          else
            expect {
              shutdown2.loop!
            }.to raise_error(StandardError, "ShutDown Via: #{expected_shutdown_cmd}")  # we stub above, and have it raise an error
          end
        end
      end

      describe "if no work has been done (i.e. last_complete_file is not there)" do

        let(:idle_seconds) { 12000 }

        it 'determines the idle time from the server-start file if workers-start is not present and compares vs the idlePostWork specification (idlePreWork:10800+300)' do
          pretend_now_is(DateTime.parse('2018-07-25 11:16:00 EDT')) do
            File.delete(last_complete_file) rescue nil
            File.delete(workers_start_file) rescue nil
            FileUtils.touch(server_start_file, :mtime => (Time.now.utc - idle_seconds))

            if expected_shutdown_cmd.nil?
              # For SHUTDOWN_NOTIFY_FILE case, expect normal completion, not an error
              expect {
                shutdown.loop!
                # it should eventually shut down
              }.not_to raise_error
            else
              # For other shutdown methods, expect error to be raised
              expect {
                shutdown.loop!
                # it should eventually shut down
              }.to raise_error(StandardError, "ShutDown Via: #{expected_shutdown_cmd}")  # we stub above, and have it raise an error
            end

            expect(system_calls).to include(stop_runners_script)
            if !expected_shutdown_cmd.nil?
              expect(system_calls.last).to eq(expected_shutdown_cmd)
            end
          end
        end

        it 'determines the idle time from the workers-start file and compares vs the idlePostWork specification (idlePreWork:10800+300)' do
          pretend_now_is(DateTime.parse('2018-07-25 11:16:00 EDT')) do

            File.delete(last_complete_file) rescue nil
            File.open(workers_start_file, 'wb') {|f| f.puts (Time.now.utc - idle_seconds).strftime('%Y-%m-%d %H:%M:%S %Z') }

            if expected_shutdown_cmd.nil?
              # For SHUTDOWN_NOTIFY_FILE case, expect normal completion, not an error
              expect {
                shutdown.loop!
                # it should eventually shut down
              }.not_to raise_error
            else
              # For other shutdown methods, expect error to be raised
              expect {
                shutdown.loop!
                # it should eventually shut down
              }.to raise_error(StandardError, "ShutDown Via: #{expected_shutdown_cmd}")  # we stub above, and have it raise an error
            end

            expect(system_calls).to include(stop_runners_script)
            if !expected_shutdown_cmd.nil?
              expect(system_calls.last).to eq(expected_shutdown_cmd)
            end
          end
        end

        describe 'elapsed time' do
          let(:shutdown_spec) { 'elapsedPreWork:10800+300,elapsedPostWork:730+10' }
          it 'determines the elapsed time from the workers-start file and compares irrespective of the PostWork specification' do

            idle_seconds = 12000

            pretend_now_is(DateTime.parse('2018-07-25 11:16:00 EDT')) do

              File.delete(last_complete_file) rescue nil
              File.open(workers_start_file, 'wb') { |f| f.puts (Time.now.utc - idle_seconds).strftime('%Y-%m-%d %H:%M:%S %Z') }

              if expected_shutdown_cmd.nil?
                expect {
                  shutdown.loop!
                  # it should eventually shut down
                }.not_to raise_error
              else
                expect {
                  shutdown.loop!
                  # it should eventually shut down
                }.to raise_error(StandardError, "ShutDown Via: #{expected_shutdown_cmd}") # we stub above, and have it raise an error
              end

              expect(system_calls).to include(stop_runners_script)
              if !expected_shutdown_cmd.nil?
                expect(system_calls.last).to eq(expected_shutdown_cmd)
              end

            end

          end
        end

      end

      describe "if work has been done (last_complete_file is there)" do
        it 'determines the idle time from the last-completion file and shuts down comparing against idlePosWork e.g. idlePostWork:730+10' do

          worker_start_sec = 1802
          idle_seconds = 825

          pretend_now_is(DateTime.parse('2018-07-25 11:16:00 EDT')) do

            File.open(last_complete_file, 'wb') {|f| f.puts (Time.now.utc - idle_seconds).strftime('%Y-%m-%d %H:%M:%S %Z') }
            File.open(workers_start_file, 'wb') {|f| f.puts (Time.now.utc - worker_start_sec).strftime('%Y-%m-%d %H:%M:%S %Z') }

            if expected_shutdown_cmd.nil?
              # For SHUTDOWN_NOTIFY_FILE case, expect normal completion, not an error
              expect {
                shutdown.loop!
                # it should eventually shut down
              }.not_to raise_error
            else
              # For other shutdown methods, expect error to be raised
              expect {
                shutdown.loop!
                # it should eventually shut down
              }.to raise_error(StandardError, "ShutDown Via: #{expected_shutdown_cmd}")  # we stub above, and have it raise an error
            end

            expect(system_calls).to include(stop_runners_script)
            if !expected_shutdown_cmd.nil?
              expect(system_calls.last).to eq(expected_shutdown_cmd)
            end
          end

        end


      end

      describe 'detecting an error log file' do

        it 'no longer prevents shutdown - it will shutdown with no extra action for now' do

          idle_seconds = 825

          pretend_now_is(DateTime.parse('2018-07-25 11:16:00 EDT')) do

            File.open(workers_start_file, 'wb') {|f| f.puts 'anything' }
            File.open(last_complete_file, 'wb') {|f| f.puts (Time.now.utc - idle_seconds).strftime('%Y-%m-%d %H:%M:%S %Z') }
            File.open(last_error_file, 'wb') {|f| f.puts (Time.now.utc - idle_seconds).strftime('%Y-%m-%d %H:%M:%S %Z') }

            if expected_shutdown_cmd.nil?
              # For SHUTDOWN_NOTIFY_FILE case, expect normal completion, not an error
              expect {
                shutdown.loop!
                # it should eventually shut down
              }.not_to raise_error
            else
              # For other shutdown methods, expect error to be raised
              expect {
                shutdown.loop!
                # it should eventually shut down
              }.to raise_error(StandardError, "ShutDown Via: #{expected_shutdown_cmd}")  # we stub above, and have it raise an error
            end

            expect(system_calls).to include('echo errors-present-but-continuing-with-shutdown')
            if !expected_shutdown_cmd.nil?
              expect(system_calls.last).to eq(expected_shutdown_cmd)
            end
          end

        end

      end

    end

    describe "shutdown stale time discovery" do

      describe "with a spec like idlePreWork:900+0,idlePostWork:400+0" do
        let(:shutdown_spec) { 'idlePreWork:900+0,idlePostWork:400+0' }
        it 'should have a time threshold of exactly 900 seconds pre-work and 400 seconds post-work' do
          prework, postwork = shutdown.time_thresholds
          expect(prework).to equal(900)
          expect(postwork).to equal(400)
        end
      end

      describe "with standard spec like idlePreWork:800+10,idlePostWork:400+10" do
        let(:shutdown_spec) { 'idlePreWork:800+10,idlePostWork:400+10' }
        it 'should have a time threshold of 800+rand(0..10) seconds pre-work and 400+rand(0..10) seconds post-work' do
          prework, postwork = shutdown.time_thresholds
          expect(prework - 805).to be <= 5
          expect(postwork - 405).to be <= 5
        end
      end

      describe "with a spec like 0600-1200::idlePreWork:10800+10,idlePostWork:800+10;idlePreWork:900+10,idlePostWork:90+10" do
        let(:shutdown_spec) { '0600-1200::idlePreWork:10800+10,idlePostWork:800+10;idlePreWork:900+10,idlePostWork:90+10' }

        it 'should have 10800 + rand(0..10) for pre-work and 800 + rand(0..10) for post-work during Central Time hours 0600-1200' do
          pretend_now_is(DateTime.parse('2018-07-25 07:42:24 CDT')) do
            prework, postwork = shutdown.time_thresholds
            expect(prework - 10805).to be <= 5
            expect(postwork - 805).to be <= 5
          end

        end
        it 'should have 900 + rand(0..10) for pre-work and 90+rand(0..10) post-work during other hours' do
          pretend_now_is(DateTime.parse('2018-07-25 02:42:24 CDT')) do
            prework, postwork = shutdown.time_thresholds
            expect(prework - 905).to be <= 5
            expect(postwork - 95).to be <= 5
          end
        end
      end
    end
  end
  
  describe "when env vars for TIOS_AWS_URL and TAG_SELF_SHUTDOWN_TIOSAWS_ENDPOINT are set" do
    let(:env_tios_aws_url) { "https://some-management.tioscapital.com"}
    let(:env_self_shutdown_tiosaws_endpoint) { "instances/self_shutdown_terminate" }
    let(:expected_shutdown_cmd) {  "curl -s -d \"instance_id=#{instance_id}\" -X POST #{env_tios_aws_url}/#{env_self_shutdown_tiosaws_endpoint}" }
    
    include_examples 'shutdown verifications'
  end
  
  describe "when env var TIOS_AWS_URL is set but TAG_SELF_SHUTDOWN_TIOSAWS_ENDPOINT is not set" do
    let(:env_tios_aws_url) { "https://some-management.tioscapital.com"}
    let(:env_self_shutdown_tiosaws_endpoint) { nil }
    let(:expected_shutdown_cmd) {  "sudo shutdown -h now" } 

    include_examples 'shutdown verifications'
  end
  
  describe "when SHUTDOWN_NOTIFY_FILE environment variable is set" do
    let(:env_tios_aws_url) { "https://some-management.tioscapital.com"}
    let(:env_self_shutdown_tiosaws_endpoint) { "instances/self_shutdown_terminate" }
    let(:shutdown_notify_file) { "#{temp_dir}/shutdown_notify.txt" }
    let(:expected_shutdown_cmd) { nil } # No system command expected, just file creation
    
    before(:each) do
      allow(ENV).to receive(:[]).with('SHUTDOWN_NOTIFY_FILE').and_return(shutdown_notify_file)
      # Still mock other environment variables but they should not be used since SHUTDOWN_NOTIFY_FILE takes precedence
      allow(ENV).to receive(:[]).with('TIOS_AWS_URL').and_return(env_tios_aws_url)
      allow(ENV).to receive(:[]).with('TAG_SELF_SHUTDOWN_TIOSAWS_ENDPOINT').and_return(env_self_shutdown_tiosaws_endpoint)
    end
    
    include_examples 'shutdown verifications'
    
    describe "notification file creation behavior" do
      
      let(:shutdown_spec) { 'idlePreWork:10800+300,idlePostWork:730+10' }
      
      before(:each) do
        File.delete(workers_start_file) rescue nil
        File.delete(last_complete_file) rescue nil
        File.delete(last_error_file) rescue nil
        File.delete(server_start_file) rescue nil
        File.delete(shutdown_notify_file) rescue nil
        
        @num_running_processes = 1
        @num_working_processes = 1
        
        allow_any_instance_of(ResqueSelfShutdown::Runner).to receive(:command_output) do |obj,cmd|
          system_calls << cmd
          
          case(cmd)
          when "pgrep -fcx '#{process_running_regex}'"
            @num_running_processes.to_s
          when "pgrep -fcx '#{process_working_regex}'"
            @num_working_processes.to_s
          when "echo errors-present-but-continuing-with-shutdown"
            "errors-present-but-continuing-with-shutdown"
          else
            cmd
          end
        end
        
        allow(shutdown).to receive(:sleep) do |stime|
          sleep_times << stime
          # After a couple sleeps, we are down to 0 working
          if sleep_times.select {|s| s == sleep_time}.count >= 2
            @num_running_processes = 1
            @num_working_processes = 0
          end
          # After a couple of sleeps after post-stop-workers, we are down to 0 running, 0 working
          if sleep_times.select {|s| s == sleep_time_during_shutdown }.count >= 2
            @num_running_processes = 0
            @num_working_processes = 0
          end
        end
      end
      
      it 'creates notification file with timestamp when shutdown conditions are met' do
        idle_seconds = 825
        
        pretend_now_is(DateTime.parse('2018-07-25 11:16:00 EDT')) do
          File.open(last_complete_file, 'wb') {|f| f.puts (Time.now.utc - idle_seconds).strftime('%Y-%m-%d %H:%M:%S %Z') }
          File.open(workers_start_file, 'wb') {|f| f.puts (Time.now.utc - 1802).strftime('%Y-%m-%d %H:%M:%S %Z') }
          
          # Shutdown should complete normally without raising an error (no system shutdown command)
          expect { shutdown.loop! }.not_to raise_error
          
          # Verify the notification file was created
          expect(File.exist?(shutdown_notify_file)).to be true
          
          # Verify the file contains a properly formatted timestamp
          file_content = File.read(shutdown_notify_file).strip
          expect(file_content).to match(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \w+/)
          
          # Verify the timestamp is reasonably current (within last few seconds)
          parsed_time = Time.strptime(file_content, '%Y-%m-%d %H:%M:%S %Z')
          expect(parsed_time).to be_within(10).of(Time.now)
          
          # Verify stop script was still called
          expect(system_calls).to include(stop_runners_script)
        end
      end
      
      it 'creates parent directories if they do not exist' do
        nested_notify_file = "#{temp_dir}/deep/nested/path/shutdown_notify.txt"
        allow(ENV).to receive(:[]).with('SHUTDOWN_NOTIFY_FILE').and_return(nested_notify_file)
        
        idle_seconds = 825
        
        pretend_now_is(DateTime.parse('2018-07-25 11:16:00 EDT')) do
          File.open(last_complete_file, 'wb') {|f| f.puts (Time.now.utc - idle_seconds).strftime('%Y-%m-%d %H:%M:%S %Z') }
          File.open(workers_start_file, 'wb') {|f| f.puts (Time.now.utc - 1802).strftime('%Y-%m-%d %H:%M:%S %Z') }
          
          expect { shutdown.loop! }.not_to raise_error
          
          expect(File.exist?(nested_notify_file)).to be true
          expect(File.read(nested_notify_file).strip).to match(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \w+/)
        end
      end
      
      it 'still handles error files but proceeds with shutdown' do
        idle_seconds = 825
        
        pretend_now_is(DateTime.parse('2018-07-25 11:16:00 EDT')) do
          File.open(workers_start_file, 'wb') {|f| f.puts 'anything' }
          File.open(last_complete_file, 'wb') {|f| f.puts (Time.now.utc - idle_seconds).strftime('%Y-%m-%d %H:%M:%S %Z') }
          File.open(last_error_file, 'wb') {|f| f.puts (Time.now.utc - idle_seconds).strftime('%Y-%m-%d %H:%M:%S %Z') }
          
          expect { shutdown.loop! }.not_to raise_error
          
          # Should still create the notification file despite errors
          expect(File.exist?(shutdown_notify_file)).to be true
          
          # Should still log that errors were present
          expect(system_calls).to include('echo errors-present-but-continuing-with-shutdown')
        end
      end
    end
  end
  
  describe '#get_env_var' do
    it 'returns the environment var' do
      allow(ENV).to receive(:[]).with('FOO').and_return("123")
      expect(shutdown.send(:get_env_var, 'FOO')).to eq('123')
    end
    
    it 'returns nil if the env var is an empty string' do
      allow(ENV).to receive(:[]).with('FOO').and_return("")
      expect(shutdown.send(:get_env_var, 'FOO')).to be_nil      
    end
    
    it 'returns nil if the env var does not exist' do
      allow(ENV).to receive(:[]).with('FOO').and_return(nil)
      expect(shutdown.send(:get_env_var, 'FOO')).to be_nil      
    end
  end
  
  describe '#get_instance_id' do
    it 'gets the instance id via AWS self-check url' do
      sd = ResqueSelfShutdown::Runner.new(config_file)
      expect(sd).to receive(:command_output).with("curl -s http://169.254.169.254/latest/meta-data/instance-id").and_return(instance_id)
      expect(sd.send(:get_instance_id)).to eq(instance_id)
    end
  end
  
  describe '#create_shutdown_notification_file' do
    it 'creates file with current timestamp in system timezone' do
      test_file = "#{temp_dir}/test_shutdown_notify.txt"
      sd = ResqueSelfShutdown::Runner.new(config_file)
      
      # Ensure file doesn't exist initially
      expect(File.exist?(test_file)).to be false
      
      # Create the notification file
      sd.send(:create_shutdown_notification_file, test_file)
      
      # Verify file was created
      expect(File.exist?(test_file)).to be true
      
      # Verify file content format
      content = File.read(test_file).strip
      expect(content).to match(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \w+/)
      
      # Verify timestamp is current (within last 5 seconds)
      parsed_time = Time.strptime(content, '%Y-%m-%d %H:%M:%S %Z')
      expect(parsed_time).to be_within(5).of(Time.now)
    end
    
    it 'creates parent directories when they do not exist' do
      nested_test_file = "#{temp_dir}/deeply/nested/path/shutdown_notify.txt"
      sd = ResqueSelfShutdown::Runner.new(config_file)
      
      # Ensure parent directories don't exist
      expect(File.exist?(File.dirname(nested_test_file))).to be false
      
      # Create the notification file
      sd.send(:create_shutdown_notification_file, nested_test_file)
      
      # Verify file and parent directories were created
      expect(File.exist?(nested_test_file)).to be true
      expect(File.directory?(File.dirname(nested_test_file))).to be true
      
      # Verify file content
      content = File.read(nested_test_file).strip
      expect(content).to match(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \w+/)
    end
  end
  

  it "has a version number" do
    expect(ResqueSelfShutdown::VERSION).not_to be nil
  end

end
