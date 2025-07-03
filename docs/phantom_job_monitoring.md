# PhantomBuster Job Monitoring Implementation

## Problem
PhantomBuster jobs were getting stuck in "pending" status without proper timeout handling. Some jobs were stuck for over 24 hours, blocking system resources and preventing new extractions.

## Solution
Implemented a multi-layered monitoring system to prevent and handle stuck PhantomBuster jobs.

### 1. PhantomJobMonitorWorker
- **Purpose**: Monitor and timeout stuck PhantomBuster jobs
- **Timeout**: 10 minutes (configurable via `PHANTOM_TIMEOUT_MINUTES`)
- **Location**: `app/workers/phantom_job_monitor_worker.rb`
- **Features**:
  - Finds all pending jobs older than timeout threshold
  - Updates job status to "failed" with appropriate error message
  - Preserves audit trail with timeout metadata
  - Handles jobs with or without container IDs

### 2. Enhanced PersonProfileExtractionAsyncService
- **Improvements**:
  - Better error handling for phantom launch failures
  - Validates container ID before proceeding
  - Adds error metadata to audit logs for failed status validation
  - Improved logging for debugging launch issues
  - Handles API timeouts gracefully

### 3. Monitoring Tools
Created rake tasks for monitoring and management:

```bash
# Check current phantom job status
bundle exec rake phantom:status

# Manually run the monitor (timeout stuck jobs)
bundle exec rake phantom:monitor

# Run continuous monitoring (every 5 minutes)
bundle exec rake phantom:schedule_monitor
```

### 4. Safety Mechanisms
1. **Primary Status Check**: Scheduled via `PersonProfileExtractionStatusWorker`
2. **Backup Monitor**: `PhantomJobMonitorWorker` scheduled 11 minutes after launch
3. **Manual Monitoring**: Can be triggered via rake tasks or cron jobs

### 5. Testing
Comprehensive test coverage added:
- `spec/workers/phantom_job_monitor_worker_spec.rb` - 11 test cases
- `spec/services/person_profile_extraction_async_service_spec.rb` - 18 test cases

## Usage

### Automatic Monitoring
The system automatically schedules a monitor check 11 minutes after each phantom job launch:

```ruby
PhantomJobMonitorWorker.perform_in(11.minutes)
```

### Manual Monitoring
For production systems, set up a cron job to run the monitor regularly:

```bash
# Add to crontab
*/5 * * * * cd /path/to/app && bundle exec rake phantom:monitor
```

### Checking Job Status
```bash
# View all pending jobs and recent failures
bundle exec rake phantom:status
```

## Configuration

### Timeout Duration
Adjust the timeout in `PhantomJobMonitorWorker`:
```ruby
PHANTOM_TIMEOUT_MINUTES = 10  # Default: 10 minutes
```

### Recurring Monitoring
To enable automatic recurring monitoring, add to Gemfile:
```ruby
gem 'sidekiq-cron'
```

Then uncomment the configuration in `config/initializers/sidekiq_cron.rb`.

## Metrics and Monitoring

The system tracks:
- Total stuck jobs found and timed out
- Job duration before timeout
- Container IDs (when available)
- Error messages and stack traces
- Timeout timestamps

All information is preserved in the ServiceAuditLog metadata for debugging and analysis.

## Future Improvements
1. Implement `PersonProfileExtractionCheckWorker` as additional safety layer
2. Add alerting when jobs timeout frequently
3. Implement retry logic for transient failures
4. Add metrics dashboard for phantom job success rates