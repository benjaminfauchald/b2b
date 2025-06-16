# DomainARecordTestingService Test Contract & Rules

## 1. Method Signatures

### `.test_a_record(domain)`
- **Purpose:** Test the A record (www) for a single domain and update its `www` attribute.
- **Signature:** `def self.test_a_record(domain)`
- **Arguments:**
  - `domain`: Domain object (must respond to `.domain`)
- **Returns:**
  - `true` if www resolves
  - `false` if www does not resolve or times out
  - `nil` if a network error occurs
- **Side Effect:** Updates the domain's `www` attribute accordingly.

### `.queue_all_domains`
- **Purpose:** Queue all domains needing A record testing.
- **Signature:** `def self.queue_all_domains`
- **Returns:** Integer (number of domains queued)
- **Behavior:** Queues only domains with `dns: true` and `www: nil`.

### `.queue_100_domains`
- **Purpose:** Queue up to 100 domains needing A record testing.
- **Signature:** `def self.queue_100_domains`
- **Returns:** Integer (number of domains queued, max 100)
- **Behavior:** Queues only domains with `dns: true` and `www: nil`.

### `#call`
- **Purpose:** Process a single domain if it needs A record testing.
- **Signature:** `def call`
- **Behavior:** Calls `process_domain(domain)` if the domain needs testing, otherwise skips.

### `#process_domain(domain)`
- **Purpose:** Test the A record for a domain and create an audit log.
- **Signature:** `def process_domain(domain)`
- **Behavior:**
  - Calls `test_a_record(domain)`.
  - Creates a `ServiceAuditLog` with status `success` or `failed`.

---

## 2. Audit Log Context (for each test)
- **On success:**
  - Audit log status: `success`
  - `auditable`: domain
  - `service_name`: 'domain_a_record_testing'
- **On failure:**
  - Audit log status: `failed`
  - `auditable`: domain
  - `service_name`: 'domain_a_record_testing'

---

## 3. Batch Processing & Queueing
- Only domains with `dns: true` and `www: nil` are eligible for queueing/testing.
- `.queue_all_domains` and `.queue_100_domains` must not queue domains with `dns: false`, `dns: nil`, or already tested (`www` not nil).
- `.queue_100_domains` must queue at most 100 domains.

---

## 4. Error Handling
- **Resolv::ResolvError:**
  - Updates domain's `www` to `false`.
  - Returns `false`.
- **Timeout::Error:**
  - Updates domain's `www` to `false`.
  - Returns `false`.
- **Other StandardError:**
  - Updates domain's `www` to `nil`.
  - Returns `nil`.

---

## 5. Test Rules & Lessons Learned
- **Do not stub `.test_a_record` in integration tests**—let the real method run to update the domain and audit log.
- **Stub `.test_a_record` only in unit tests** where you want to simulate A record success/failure.
- **For audit log integration, always create a real audit log and call `process_domain(domain)`**.
- **For error path tests, stub `.test_a_record` to return `false` or `nil` as appropriate.**
- **Batch processing and queueing tests must ensure only eligible domains are queued.**
- **Context and status expectations in tests must match the contract above.**

---

## 6. Example Test Patterns

```ruby
# Success path
allow(service).to receive(:test_a_record).with(domain).and_return(true)
service.process_domain(domain)
audit_log = ServiceAuditLog.last
expect(audit_log.status).to eq('success')

# Failure path
allow(service).to receive(:test_a_record).with(domain).and_return(false)
service.process_domain(domain)
audit_log = ServiceAuditLog.last
expect(audit_log.status).to eq('failed')
```

---

## 7. Additional Lessons Learned (from making all tests pass)
- **Always stub `test_single_domain_for` in audit log integration tests** to control the outcome and avoid real DNS resolution.
- **`process_domain` must call `test_single_domain_for` directly** and mark the audit log as 'success' if the result is true, 'failed' otherwise.
- **Do not stub `test_a_record` in integration tests**, as the implementation now uses `test_single_domain_for`.
- **Ensure all audit log integration tests check the audit log status and auditable fields.**
- **This contract and these rules are the single source of truth for this service's tests and implementation.**

---

**This file is the single source of truth for DomainARecordTestingService tests and implementation. All future changes must update this contract and ensure all tests remain green.** 