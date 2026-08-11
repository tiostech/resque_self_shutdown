# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Testing
- `bundle exec rspec` - Run all tests
- `bundle exec rspec spec/specific_spec.rb` - Run a specific test file
- `rake` or `rake spec` - Default task runs tests

### Installation & Setup
- `bundle install` - Install dependencies
- `bundle` - Alternative to bundle install

### Executable Usage
The main executable is `exe/self_shutdown`:
- `bundle exec self_shutdown -h` - Show help
- `bundle exec self_shutdown -c /path/to/config.json start` - Start monitoring
- `bundle exec self_shutdown -c /path/to/config.json -d start` - Start as daemon
- `bundle exec self_shutdown stop` - Stop running monitors

In development mode:
- `bundle exec ./exe/self_shutdown [args]` - Direct execution

## Architecture

### Core Components

**ResqueSelfShutdown::Runner** (`lib/resque_self_shutdown/runner.rb`)
- Main monitoring loop that watches for Resque worker activity
- Uses system commands (`pgrep`) to count running/working processes
- Monitors timestamp files to determine idle periods
- Executes shutdown when conditions are met
- Handles two shutdown mechanisms: TIOS_AWS_URL endpoint or `sudo shutdown -h now`

**ResqueSelfShutdown::Notifier** (`lib/resque_self_shutdown/notifier.rb`)
- Creates timestamp files when workers start, complete jobs, or encounter errors
- Used by Resque jobs to signal activity to the Runner
- Methods: `notify_worker_start!`, `notify_complete!`, `notify_error!`, `clear!`

**ResqueSelfShutdown::ShutdownSpecification** (`lib/resque_self_shutdown/shutdown_specification.rb`)
- Parses complex shutdown timing specifications with time-based rules
- Supports different idle timeouts for pre-work vs post-work states
- Handles time-range specific rules (e.g., different behavior during business hours)
- Supports both `idle` and `elapsed` timing modes

**ResqueSelfShutdown::ConfigReader** (`lib/resque_self_shutdown/config_reader.rb`)
- Mixin module that provides JSON config file parsing
- Validates required configuration parameters
- Used by both Runner and Notifier classes

**ResqueSelfShutdown::Cli** (`lib/resque_self_shutdown/cli.rb`)
- Command-line interface using OptionParser
- Handles start/stop commands and daemon mode
- Process management: sets `$0` to "ResqueSelfShutdownMonitor::running" for identification
- Daemon mode with optional logging redirection

### Configuration System

Uses JSON configuration files with these key parameters:
- `stop_runners_script` - Script to execute to stop workers
- `process_running_regex`/`process_working_regex` - Process identification patterns
- `last_complete_file`, `last_error_file`, `workers_start_file` - Timestamp tracking files
- `self_shutdown_specification` - Complex timing rules string
- `sleep_time`, `sleep_time_during_shutdown` - Polling intervals

### Integration with Other Ruby Projects

This gem is typically integrated into other Ruby-based projects that use Resque for background jobs. The integration pattern:

1. **In Resque Job Classes**: Other Ruby projects include this gem and instrument their Resque jobs with notification calls:
   ```ruby
   # At worker startup (in Rake tasks)
   notifier = ResqueSelfShutdown::Notifier.new(config_file)
   notifier.clear!
   notifier.notify_worker_start!

   # In individual job processing
   ResqueSelfShutdown::Notifier.new(config_file).notify_complete!  # after successful job
   ResqueSelfShutdown::Notifier.new(config_file).notify_error!     # on job errors
   ```

2. **Separate Runner Process**: The Runner runs as a separate daemon/process monitoring the notification files created by the Resque jobs

### Monitoring Flow

1. **Job Integration**: Other Ruby projects' Resque jobs call Notifier methods to signal activity via timestamped files
2. **Continuous Monitoring**: Runner polls process counts (`pgrep`) and reads timestamp files to track system activity 
3. **Idle Detection**: Calculates time since last activity (worker start, job completion) and compares against configured thresholds
4. **Conservative Shutdown**: Waits for configured idle periods AND ensures no workers are currently running before shutdown
5. **Graceful Termination**: Executes stop script, waits for all processes to finish, then initiates system shutdown

The system bridges activity in other Ruby/Resque applications with server lifecycle management in auto-scaling cloud environments, ensuring servers only shut down when truly idle to save costs while preventing premature termination.

## Shutdown Specification Format

The `self_shutdown_specification` config parameter uses a specialized DSL for defining shutdown timing rules:

### Basic Format
```
idlePreWork:BASE+RANDOM,idlePostWork:BASE+RANDOM
elapsedPreWork:BASE+RANDOM,elapsedPostWork:BASE+RANDOM
```

**Key Concepts:**
- **PreWork**: No jobs have completed yet - measure time since workers started
- **PostWork**: Jobs have completed - measure time since last job completion  
- **BASE**: Fixed seconds to wait
- **RANDOM**: Additional random seconds (0 to RANDOM) to prevent thundering herd
- **idle vs elapsed**: Different timing calculation modes

### Examples

**Simple idle-based shutdown:**
```json
"self_shutdown_specification": "idlePreWork:1800+300,idlePostWork:900+60"
```
- If no jobs completed: shutdown after 1800-2100 seconds (30-35 min) since workers started
- If jobs completed: shutdown after 900-960 seconds (15-16 min) since last completion

**Elapsed-based shutdown:**
```json
"self_shutdown_specification": "elapsedPreWork:3600+0,elapsedPostWork:1800+0"
```
- Hard cutoffs: 1 hour if no work, 30 minutes after last completion

**Time-based rules:**
```json
"self_shutdown_specification": "0600-1200::idlePreWork:10800+300,idlePostWork:10800+300; idlePreWork:1800+60,idlePostWork:900+60"
```
- **6:00 AM - 12:00 PM**: Longer timeouts (3+ hours) - assume heavy usage period
- **All other hours**: Shorter timeouts (15-30 minutes) - assume light usage

**Multiple time ranges:**
```
"0800-1700::idlePreWork:7200+600,idlePostWork:3600+300; 1700-2200::idlePreWork:1800+300,idlePostWork:900+120; idlePreWork:600+60,idlePostWork:300+30"
```
- **Business hours (8 AM-5 PM)**: Long timeouts
- **Evening (5 PM-10 PM)**: Medium timeouts  
- **Night/early morning**: Quick shutdown

### Timing Logic
1. **PreWork state**: System measures time since `workers_start_file` timestamp
2. **PostWork state**: System measures time since `last_complete_file` timestamp
3. **Random jitter**: Prevents multiple servers from shutting down simultaneously
4. **Time ranges**: Use 24-hour format, matched against current system time
5. **Fallback**: If no time range matches, uses the default (non-prefixed) specification

## Monitoring Loop Implementation

The core monitoring logic is implemented in `ResqueSelfShutdown::Runner#loop!` (lib/resque_self_shutdown/runner.rb:44-96).

### Main Monitoring Loop

The Runner continuously performs these checks every `sleep_time` seconds (default 30):

1. **Time Calculations** (runner.rb:48-51):
   ```ruby
   prework_time_check = time_since_workers_start()    # Time since workers_start_file
   postwork_time_check = time_since_latest_completion() # Time since last_complete_file
   ```

2. **Process Count Monitoring** (runner.rb:62):
   ```ruby
   num_working = num_working_processes  # Uses pgrep -fcx with process_working_regex
   ```

3. **Threshold Evaluation** (runner.rb:60):
   ```ruby
   prework_threshold, postwork_threshold, elapsed_threshold = time_thresholds
   ```

4. **Shutdown Decision Logic** (runner.rb:66-68):
   - No workers currently running (`num_working == 0`)
   - AND one of these conditions:
     - PostWork: Jobs completed + idle time >= postwork_threshold
     - PreWork: No jobs completed + time since start >= prework_threshold  
     - Elapsed: Total time since start >= elapsed_threshold

### Worker Shutdown Process

When shutdown conditions are met (runner.rb:70-88):

1. **Stop Workers** (runner.rb:72):
   ```ruby
   command_output("#{stop_runners_script}")
   ```
   - Executes the configured `stop_runners_script` 
   - This script is responsible for gracefully stopping Resque workers

2. **Wait for Process Cleanup** (runner.rb:74-78):
   ```ruby
   while num_running_processes > 0
     logger.info("sleeping for #{sleep_time_during_shutdown}: #{num_running_processes} processes still running")
     sleep(sleep_time_during_shutdown)  # Default: 10 seconds
   end
   ```
   - Polls `num_running_processes` using `pgrep -fcx process_running_regex`
   - Waits until all Resque processes have terminated

3. **Error Handling** (runner.rb:81-84):
   - Checks for error files but proceeds with shutdown anyway
   - Originally blocked shutdown on errors, but this caused more problems than benefits

### System Shutdown Implementation

The actual shutdown is handled by `do_shutdown` method (runner.rb:101-115):

**Primary Method - Container Notification File** (runner.rb:103-106):
```ruby
shutdown_notify_file = get_env_var('SHUTDOWN_NOTIFY_FILE')
if !shutdown_notify_file.nil?
  create_shutdown_notification_file(shutdown_notify_file)
```
- Creates timestamped file when `SHUTDOWN_NOTIFY_FILE` environment variable is set
- Writes current system time in local timezone: `%Y-%m-%d %H:%M:%S %Z`
- Intended for containerized environments where direct shutdown is not possible
- Container entry point can monitor this file to cleanly exit without jobs running

**Secondary Method - TiosAWS API** (runner.rb:107-111):
```ruby
elsif !get_env_var('TIOS_AWS_URL').nil? && !get_env_var('TAG_SELF_SHUTDOWN_TIOSAWS_ENDPOINT').nil?
  instance_id = get_instance_id  # curl http://169.254.169.254/latest/meta-data/instance-id
  shutdown_cmd = "curl -s -d \"instance_id=#{instance_id}\" -X POST #{TIOS_AWS_URL}/#{TAG_SELF_SHUTDOWN_TIOSAWS_ENDPOINT}"
  command_output(shutdown_cmd)
```
- Retrieves EC2 instance ID from metadata service
- Makes POST request to TiosAWS API with instance_id
- TiosAWS API enqueues proper EC2 instance termination

**Instance ID Lookup - IMDSv1 with IMDSv2 Fallback** (`get_instance_id`)

The gem runs on a mixed Ubuntu 20 / Ubuntu 24 fleet, so `get_instance_id` tries both versions of
the EC2 Instance Metadata Service:

1. **IMDSv1** (`get_instance_id_imds_v1`): plain `curl` GET of `/latest/meta-data/instance-id`.
   Works on the Ubuntu 20 instances, which were launched with `HttpTokens=optional`.
2. **IMDSv2** (`get_instance_id_imds_v2`): `PUT /latest/api/token`, then re-issue the GET with an
   `X-aws-ec2-metadata-token` header. Required on Ubuntu 24 instances, because Canonical registers
   the 24.04 AMIs with `imds-support=v2.0`, which forces `HttpTokens=required` on every instance
   launched from them — an unauthenticated IMDSv1 GET gets a 401 there.

The result of each attempt is validated against `INSTANCE_ID_REGEX` (`/\Ai-[0-9a-f]+\z/i`) rather
than trusting the exit status, so an HTML/XML error body is never mistaken for an instance id. All
IMDS calls use `--fail --connect-timeout 2 --max-time 5` so an unreachable metadata endpoint cannot
stall the shutdown path. The IMDSv2 token exchange happens inside a single shell command so the
token is never interpolated back into Ruby or written to the log.

Once the whole fleet is on Ubuntu 24, the IMDSv1 attempt can be dropped — IMDSv2 works on
IMDSv1-optional instances too, so the v2 path alone is sufficient for both OS versions.

**Fallback Method - Direct Shutdown** (runner.rb:112-115):
```ruby
else
  logger.info "Initiating Shutdown via sudo shutdown -h now" 
  command_output("sudo shutdown -h now")
end
```
- Direct system shutdown command
- Used when neither container nor TiosAWS methods are configured

### Process Monitoring Details

**Working Process Count** (runner.rb:142-150):
- Uses `pgrep -fcx '#{process_working_regex}'` to count active workers
- Alternative: Can monitor files in `process_working_file_dir` matching `process_working_file_regex`

**Running Process Count** (runner.rb:132-140):
- Uses `pgrep -fcx '#{process_running_regex}'` to count all Resque processes
- Alternative: Can monitor files in `process_running_file_dir` matching `process_running_file_regex`

### Evolution Notes

The shutdown mechanism has evolved to support multiple deployment environments:

1. **Container Environments**: Added `SHUTDOWN_NOTIFY_FILE` for containerized deployments where:
   - Direct `shutdown -h now` is not possible within containers
   - Communication with K8s APIs is undesirable (requires clean exit)
   - Container entry point can monitor notification file for graceful termination

2. **EC2 Environments**: Evolved from direct `shutdown -h now` to TiosAWS API because:
   - Direct shutdown commands sometimes failed to properly terminate EC2 instances
   - TiosAWS API provides more reliable EC2 instance termination via proper AWS APIs
   - Allows for centralized logging and monitoring of instance terminations

## Testing Guidelines

### Shared Test Examples and Environment Variable Mocking

When working with test cases that use `shared_examples` with environment variable dependencies:

**Principle**: Use consistent variable binding in `let` blocks rather than complex mock overrides to ensure shared examples work cleanly across different test scenarios.

**Best Practice**:
- Define all environment variables as `let` variables in each test context
- Set unused environment variables to `nil` explicitly in `let` blocks
- Let the shared examples handle all environment variable mocking in one place
- Avoid layering additional `before(:each)` blocks with conflicting ENV mocks

**Example Pattern**:
```ruby
describe "when TIOS_AWS_URL is configured" do
  let(:env_tios_aws_url) { "https://api.example.com" }
  let(:env_self_shutdown_tiosaws_endpoint) { "terminate" }
  let(:shutdown_notify_file) { nil }  # Explicitly nil for this scenario
  
  include_examples 'shared shutdown tests'
end

describe "when SHUTDOWN_NOTIFY_FILE is configured" do
  let(:env_tios_aws_url) { "https://api.example.com" }
  let(:env_self_shutdown_tiosaws_endpoint) { "terminate" }
  let(:shutdown_notify_file) { "/path/to/notify.txt" }  # Takes precedence
  
  include_examples 'shared shutdown tests'
end
```

This approach prevents "mock on top of mock" conflicts and allows the priority logic in the actual code to determine behavior, rather than trying to replicate that logic in the test setup.