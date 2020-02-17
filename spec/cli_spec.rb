require 'spec_helper'
require 'resque_self_shutdown/cli'

RSpec.describe ResqueSelfShutdown::Cli do
  it 'deals with errant arguments' do
    argv = %w( --stop-runners-script /usr/bin/env)

    expect {
      ResqueSelfShutdown::Cli.start!(argv)
    }.to raise_error(ArgumentError)

  end
  it 'processes arguments' do
    argv = %w( --stop-runners-script /usr/bin/env --process-running-regex foo --process-working-regex bar --last-complete-file /tmp/lastcomplete.txt --last-error-file /tmp/lasterror.txt --workers-start-file /tmp/workerstart.txt idlePreWork:123+10,idlePostWork:22+10)

    loop_calls = 0
    allow_any_instance_of(ResqueSelfShutdown::Runner).to receive(:loop!) do |ss|

      loop_calls += 1

      # verify options passing
      expect(ss.shutdown_spec.to_s).to eq('idlePreWork:123+10,idlePostWork:22+10')
      expect(ss.process_running_regex).to eq('foo')
      expect(ss.process_working_regex).to eq('bar')
      expect(ss.stop_runners_script).to eq('/usr/bin/env')
      expect(ss.last_complete_file).to eq('/tmp/lastcomplete.txt')
      expect(ss.last_error_file).to eq('/tmp/lasterror.txt')
      expect(ss.workers_start_file).to eq('/tmp/workerstart.txt')

    end

    ResqueSelfShutdown::Cli.start!(argv)

    expect(loop_calls).to eq(1)
  end
end
