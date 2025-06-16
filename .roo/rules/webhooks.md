---
description: 
globs: 
alwaysApply: false
---
These are webhook-specific rules and best practices for this Rails project

- All webhook endpoints must be implemented in a dedicated controller under `app/controllers/webhooks/`.

- Each webhook must have a corresponding service object in `app/services/webhooks/` for business logic.

- Webhook controllers must inherit from `ActionController::API` and not include session/cookie middleware.

- All incoming webhook requests must be authenticated using a secret token or HMAC signature, validated before any processing.

- Webhook payloads must be logged (with sensitive data redacted) for auditability, using the Service Control Table (SCT) system if possible.

- Webhook endpoints must respond quickly (within 2s) and offload heavy processing to background jobs (e.g., Sidekiq).

- All webhook events must be idempotent: repeated delivery of the same event must not cause duplicate side effects.

- Webhook routes must be defined under a dedicated namespace in `config/routes.rb` (e.g., `namespace :webhooks do ... end`).

- All webhook-related code must be covered by request specs and service specs in `spec/requests/webhooks/` and `spec/services/webhooks/`.

- Webhook documentation (event types, payloads, security, retry policy) must be maintained in `docs/webhooks.md`.

- Never expose sensitive credentials or secrets in logs or error messages.

- All webhook endpoints must return appropriate HTTP status codes (200 for success, 400/401 for auth errors, 422 for validation, 500 for server errors).

- Webhook processing must be monitored and failures must be logged to the SCT and error tracking system.

- All changes to webhook logic must be reviewed for security and idempotency.


bsolutely! Here’s a best-practice strategy for deploying webhooks in a modern Rails application, with a focus on maintainability, security, and scalability.
1. Directory Structure
Controllers:
Place all webhook endpoints in a dedicated controller namespace, e.g. app/controllers/webhooks/.
Each external service (e.g. Stripe, Slack, LinkedIn) gets its own controller:
Apply to webhooks.md
.
Routes:
Namespace all webhook routes under /webhooks for clarity and security:
Apply to webhooks.md
end
Services:
Place business logic for processing webhook payloads in service objects:
Apply to webhooks.md
.
2. Security Best Practices
Authentication:
Validate signatures or secrets for each webhook (e.g., Stripe’s Stripe-Signature header).
Reject requests that fail validation with a 401 or 403.
Idempotency:
Ensure processing is idempotent (safe to retry).
Store event IDs and ignore duplicates.
Logging:
Log all received events and processing results (but never log secrets or sensitive data).
Rate Limiting:
Optionally, rate-limit incoming requests to prevent abuse.
3. Example Implementation
Controller:
Apply to webhooks.md
end
Service:
Apply to webhooks.md
end
4. Testing
Use RSpec request specs for each webhook endpoint.
Mock external service payloads and signature headers.
5. Deployment & Configuration
Environment Variables: Store webhook secrets in environment variables or Rails credentials.
SSL: Always use HTTPS for webhook endpoints.
Monitoring: Set up alerts for failed webhook deliveries or processing errors.
6. Documentation
Document all webhook endpoints, expected payloads, and security requirements in your project’s README or API docs.
Summary Table
Location	Purpose
app/controllers/webhooks/	Webhook endpoint controllers
app/services/webhooks/	Business logic for processing webhooks
config/routes.rb	Namespaced routes under /webhooks
.env/credentials	Webhook secrets and config
spec/requests/webhooks/	Request specs for webhooks
Would you like a sample controller/service generated for a specific provider, or a template for your project?