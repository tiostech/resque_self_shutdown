# ResqueSelfShutdown

A simple Ruby gem to monitor Resque workers and shut down the server when work is completed.


## Installation

Add this line to your application's Gemfile:

```ruby
git "https://github.com/tiostech/resque_self_shutdown.git" do
  gem 'resque_self_shutdown'
end
```

And then execute:

    $ bundle

## Usage


There are two sides to this:

* Notification: We provide some notification hooks for Resque workers to tell us when work is started, completed, or has errors.  Notifications are stored as timestamped files.
* Runner: We monitor Resque workers using basic system commands (pgrep) to see if Resque workers are running.  We look at the notification files (e.g. how long it has been since the last job completed)

Both sides are controlled by a single JSON configuration file that looks like this:

```json
{
  "stop_runners_script": "/path/to/stop/runners/script",
  "process_running_regex": "resque",
  "process_working_regex": "resque",
  "last_complete_file": "/path/to/log/latestJobCompleteUTC.txt",
  "last_error_file": "/path/to/log/latestJobErrorUTC.txt",
  "workers_start_file": "/path/to/log/workersStartedUTC.txt",
  "self_shutdown_specification": "idlePreWork:10800+300,idlePostWork:900+600",
  "sleep_time": 30,
  "sleep_time_during_shutdown": 10
}
```

Here are explanations of the parameters:

* "stop_runners_script": [String] the script to call to stop runners
* "process_running_regex": [String] grep string to use for searching for Resque processes running
* "process_working_regex": [String] grep string to use for searching for Resque workers doing work
* "last_complete_file": [String] path to file that will be present when a worker finishes doing work.  Contents should be timestamp: %Y-%m-%d %H:%M:%S %Z
* "last_error_file": [String] path to file that will be present when there is an error
* "workers_start_file": [String] path to file that will be present when workers start doing work.  Contents should be timestamp: %Y-%m-%d %H:%M:%S %Z
* "sleep_time": [int/String] number of seconds to sleep between checks
* "sleep_time_during_shutdown": [int/String] number of seconds to sleep between checks, after stopping workers and waiting for them to be done and then shutting down
* "self_shutdown_specification": [String] shutdown specification

The self-shutdown specification looks like this:

```ruby
  #   idlePreWork:800+10,idlePostWork:300+60 ==>
  #            If no jobs have completed, then shutdown after 800+rand(0..10) seconds since workers started
  #            If jobs have competed, then shut down after 300+rand(0..60) seconds since the last completion
  #
  #   0600-1200::idlePreWork:10800+300,idlePostWork:10800+300; idlePreWork:800+60,idlePostWork:300+60
  #       If current system (central) time is between 06:00 and 12:00 of current day...
  #            If no jobs have completed, then shutdown after 10800+rand(0..300) seconds since workers started
  #            If jobs have competed, then shut down after 10800+rand(0..300) seconds since the last completion
  #       Otherwise (all other hours)...
  #            If no jobs have completed, then shutdown after 800+rand(0..60) seconds since workers started
  #            If jobs have competed, then shut down after 300+rand(0..60) seconds since the last completion
```

Both the notification and runner should use the same configuration, so that, in particular, the notification files are the same.

The expected notification cycles are as follows.  You should include this gem and then issue notifications

```ruby
shutdown_notifier = ResqueSelfShutdown::Notifier.new(config_file)

# Inside the :start_workers Rake task:
## At the beginning of the :start_workers Rake task:
notifier = ResqueSelfShutdown::Notifier.new(config_file)
notifier.clear!
#  At the end of the :start_workers Rake task:
notifier.notify_worker_start!

# Inside job handling

## If an error happens,
ResqueSelfShutdown::Notifier.new(config_file).notify_error!

## After the job successfully completed,
ResqueSelfShutdown::Notifier.new(config_file).notify_complete!

```

Running the Self Shutdown monitor:

```bash

# help
bunlde exec self_shutdown -h

# Start:
bundle exec self_shutdown -c /path/to/shutdownconfig.json start
# Start as daemon
bundle exec self_shutdown -c /path/to/shutdownconfig.json -d start
# Start as daemon with stdout and stderr to logs
bundle exec self_shutdown -c /path/to/shutdownconfig.json -d -o /tmp/shutdown_out.log -e /tmp/shutdown_err.log start

# Kill running jobs
bundle exec self_shutdown stop

```

The psline changes to "ResqueSelfShutdownMonitor::running", which we use for killing existing runners.

Note for development mode:

```bash
# you may need to start as:
bundle exec ./exec/self_shutdown [args]
```




## Development

After checking out the repo, run `bundle install` to install dependencies. Then, run `bundle exec rspec` to run the tests.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/tisotech/resque_self_shutdown. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the ResqueSelfShutdown project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/thefooj/resque_self_shutdown/blob/master/CODE_OF_CONDUCT.md).
