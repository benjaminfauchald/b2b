# Domain Queue Integration Test

This Puppeteer test verifies that the domain testing queue system works correctly, including:
- Queue processing and drainage
- UI stat updates in real-time
- Sidekiq queue accuracy
- SCT (Service Configuration Tool) audit logging

## What It Tests

1. **Queue Processing**: Creates 50 test domains and queues them for DNS testing
2. **UI/Backend Consistency**: Monitors that UI stats match Sidekiq queue counts
3. **Real-time Updates**: Takes snapshots every 5 seconds to verify stats update properly
4. **Audit Logging**: Verifies SCT audit logs are created for each domain test
5. **Cascading Effects**: Checks that successful DNS tests trigger MX/A-record tests

## Running the Test

### Prerequisites
1. Rails server must be running: `bundle exec rake dev`
2. Sidekiq must be running: `bundle exec sidekiq`
3. You must be able to access https://local.connectica.no

### Run Command
```bash
./test/puppeteer/run_domain_queue_test.sh
```

Or directly:
```bash
node test/puppeteer/domain_queue_integration_test.js
```

## Test Output

The test will:
1. Create 50 test domains with pattern `test-domain-{timestamp}-{index}.com`
2. Login as admin user
3. Navigate to domains page
4. Queue 50 domains for DNS testing
5. Monitor stats for 30 seconds (6 snapshots at 5-second intervals)
6. Compare UI stats with backend Sidekiq stats
7. Verify SCT audit logs are created
8. Clean up test domains

### Screenshots
- `test_results/domain_queue_initial.png` - Initial state
- `test_results/domain_queue_after_queue.png` - After queueing domains
- `test_results/domain_queue_final.png` - Final state
- `test_results/domain_queue_error.png` - If error occurs

### Results File
- `test_results/domain_queue_results.json` - Detailed test results including:
  - All stat snapshots
  - Audit log samples
  - Consistency analysis
  - Pass/fail status

## Success Criteria

The test passes if:
1. UI queue counts match Sidekiq queue counts (within 2 domains tolerance)
2. SCT audit logs are created for DNS tests
3. Queue drains as domains are processed
4. Processed count increases over time
5. Follow-up queues (MX testing) are populated for successful DNS tests

## Troubleshooting

### Common Issues

1. **"Rails server is not running"**
   - Run: `bundle exec rake dev`

2. **"Sidekiq is not running"**
   - Run: `bundle exec sidekiq`

3. **Queue not draining**
   - Check Sidekiq is running
   - Check service configurations are active
   - Check for errors in Sidekiq logs

4. **UI stats not updating**
   - Check JavaScript console for errors
   - Verify WebSocket connections
   - Check Rails logs for errors

5. **Audit logs not created**
   - Verify SCT is properly configured
   - Check ServiceAuditLog model
   - Review service configuration settings