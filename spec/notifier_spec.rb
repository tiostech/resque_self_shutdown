require 'spec_helper'
require 'resque_self_shutdown/notifier'
require 'time'
require 'date'
require 'securerandom'

RSpec.describe ResqueSelfShutdown::Notifier do

  let(:now) { Time.strptime('2020-02-14 15:23:30 UTC', '%Y-%m-%d %H:%M:%S %Z').utc }

  let(:temp_dir) {
    tmp = "/tmp/foo-#{SecureRandom.uuid}"
    puts "Writing #{tmp}"
    FileUtils.mkdir_p(tmp)
    tmp
  }

  let(:notifier) {
    File.open("#{temp_dir}/config.json", 'wb') do |f|
      f.write(JSON.pretty_generate({
          :stop_runners_script => "/usr/bin/env",
          :process_running_regex => 'resque',
          :process_working_regex => 'resque',
          :last_complete_file => "#{temp_dir}/latestJobCompleteUTC.txt",
          :last_error_file => "#{temp_dir}/latestJobErrorUTC.txt",
          :workers_start_file => "#{temp_dir}/workersStartedUTC.txt",
          :self_shutdown_specification => "idlePreWork:10800+300,idlePostWork:900+600",
          :sleep_time => 30,
          :sleep_time_during_shutdown => 10
      }))
    end
    ResqueSelfShutdown::Notifier.new(config_file: "#{temp_dir}/config.json")
  }

  before(:each) do
    pretend_now_is(now)
  end

  after(:each) do
    reset_to_real_time
    puts "Deleting #{temp_dir}"
    FileUtils.rm_rf(temp_dir)
  end

  it 'notifies last-complete' do
    notifier.notify_complete!
    expect(File.read(notifier.last_complete_file)).to eq(now.strftime('%Y-%m-%d %H:%M:%S %Z'))
  end

  it 'notifies last-error' do
    notifier.notify_error!
    expect(File.read(notifier.last_error_file)).to eq(now.strftime('%Y-%m-%d %H:%M:%S %Z'))
  end

  it 'notifies workers-start' do
    notifier.notify_worker_start!
    expect(File.read(notifier.workers_start_file)).to eq(now.strftime('%Y-%m-%d %H:%M:%S %Z'))
  end
end