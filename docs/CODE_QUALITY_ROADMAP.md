# Code Quality & Automation Roadmap  
_B2B Rails Platform – 2025 Q3 → 2026 Q1_

This document describes the multi-phase plan for elevating engineering quality, observability, and automation in the **benjaminfauchald/b2b** monolith.  
It builds on existing pillars – Service objects, `ServiceAuditLog`, Sidekiq, and optional Kafka – to deliver three major capabilities:

| Phase | Capability | Target Release |
|-------|------------|----------------|
| 1 | Code Quality Dashboard | 2025-Q3 |
| 2 | Custom Rules Engine | 2025-Q4 |
| 3 | GitHub PR Integration | 2026-Q1 |

---

## 1. Code Quality Dashboard

### 1.1 Scope & Objectives
* Provide a **mission-control UI** showing real-time and historical service health.
* Surface failure hotspots, latency trends, and regression alerts derived from `ServiceAuditLog`.
* Enable drill-down to individual audit records from any graph or table.

### 1.2 Technical Approach
* **Rails MVC:**  
  * Add `app/controllers/quality_dashboard/*` for JSON + HTML endpoints.  
  * `app/views/quality_dashboard/*` using Hotwire + Tailwind for live updates.  
* **Data Source:** `ServiceAuditLog` (already indexed & rich). Create read-optimized materialized views in PostgreSQL (`service_performance_stats` already exists).  
* **Background Aggregation:**  
  * Sidekiq `QualityMetricsWorker` runs every 5 min to update roll-ups (P95 latency, error-rate).  
  * Use Redis cache for fast widget loading (< 200 ms).  
* **Alerts:**  
  * Add `QualityAlert` model (service_name, metric, threshold, status).  
  * Publish Kafka event `quality.alert.triggered` for downstream consumers / Slack bot.  
* **Auth:** Re-use Devise roles (`admin`, `analyst`) – only admins edit thresholds.

### 1.3 Implementation Phases
| Step | Deliverable | Owner | ETA |
|------|-------------|-------|-----|
| 1.1 | DB views: `daily_service_stats`, `hourly_service_stats` | BE | wk 1 |
| 1.2 | Sidekiq worker + tests | BE | wk 2 |
| 1.3 | React/Stimulus dashboard skeleton | FE | wk 3 |
| 1.4 | Live graphs (Turbo Streams) | FE | wk 4 |
| 1.5 | Alert model + Slack webhook | BE | wk 4 |
| 1.6 | Prod rollout + doc | Dev Ops | wk 5 |

### 1.4 Success Metrics
* 95 % of dashboard pages load < 500 ms.
* P1 incidents discovered via dashboard before business escalation (baseline 0 → goal ≥ 80 %).
* < 2 % Sidekiq latency overhead (measure queue times).

### 1.5 Integration Points
* `ServiceAuditLog` – primary data.
* Sidekiq – aggregation jobs.
* Kafka – optional alert streaming.
* Slack bot – incident channel notifications.

---

## 2. Custom Rules Engine

### 2.1 Scope & Objectives
* Formalize **organization-wide code & service standards** (naming, audit completeness, SLA budgets).
* Automatically evaluate every `ServiceAuditLog` entry and persisted model against these rules.
* Persist violations and expose them on the dashboard + CI checks.

### 2.2 Technical Approach
* **DSL:** `config/quality_rules.yml` (YAML) with categories (`security`, `performance`, `style`) and rule definitions (SQL/Regex/lambda).  
* **Evaluator Service:** `app/services/rules_engine.rb` iterates rules and records outcomes into new `QualityViolation` model.  
* **Execution Strategy:**  
  * Inline evaluation inside existing Service objects (`include RulesEvaluatable`) OR  
  * Post-commit Sidekiq `RulesEvaluationWorker`.  
* **Caching:** Memoize rule lookups to avoid redundant DB queries.  
* **Violation Surfacing:**  
  * Dashboard tab “Rules Compliance”.  
  * Slack/Kafka event on `severity: critical`.

### 2.3 Implementation Phases
| Step | Deliverable | Owner | ETA |
|------|-------------|-------|-----|
| 2.1 | YAML schema + validator spec | BE | wk 6 |
| 2.2 | `QualityViolation` model + migrations | BE | wk 6 |
| 2.3 | Core engine & unit tests | BE | wk 7 |
| 2.4 | Service mix-in / worker wiring | BE | wk 8 |
| 2.5 | Dashboard tab & API | FE | wk 9 |
| 2.6 | Org rule set v1 (10 rules) | Tech Lead | wk 10 |

### 2.4 Success Metrics
* 100 % of critical rules evaluated for every service run.
* ≤ 5 % false-positive rate (tracked via “dismissed” flag).
* Compliance score per service displayed on dashboard (target ≥ 90 %).

### 2.5 Integration Points
* Leverages dashboard backend & UI.
* Sidekiq for asynchronous rule evaluation.
* Kafka `quality.violation.created` topic for external consumers.

---

## 3. GitHub Pull-Request Integration

### 3.1 Scope & Objectives
* Automate **AI-assisted PR reviews** and gate merges on rule compliance + quality score.
* Post inline comments with detected issues; update PR status checks.
* Sync dashboard metrics with GitHub insights (service ↔ repo mapping).

### 3.2 Technical Approach
* **GitHub App:**  
  * Ruby `octokit` client inside new `app/services/github/*`.  
  * Webhooks → `GithubWebhookController` (events: `pull_request`, `check_run`).  
* **AI Review:** Re-use existing `services/openai.rb` (from tutorial) packaged as `AiCodeReviewer` concern.  
* **Check-run Flow:**  
  1. PR opened → webhook enqueues `PullRequestReviewWorker`.  
  2. Worker pulls patch diff, runs AI + Rules Engine.  
  3. Posts review comments + sets PR status (`success`, `neutral`, `failure`).  
* **Security:** Store GitHub App private key in Rails credentials; rotate every 90 days.

### 3.3 Implementation Phases
| Step | Deliverable | Owner | ETA |
|------|-------------|-------|-----|
| 3.1 | GitHub App registration + credentials | Dev Ops | wk 11 |
| 3.2 | Webhook controller + routing specs | BE | wk 11 |
| 3.3 | PR review worker (AI + rules) | BE | wk 12 |
| 3.4 | Inline comment formatter | BE | wk 13 |
| 3.5 | Sync metrics to dashboard | FE/BE | wk 14 |
| 3.6 | Beta rollout on internal repos | Team | wk 15 |

### 3.4 Success Metrics
* 100 % of new PRs receive automated review within 2 minutes.
* Merge-block accuracy: ≤ 5 % false negatives, ≤ 5 % false positives.
* 30 % reduction in manual review time (survey baseline).

### 3.5 Integration Points
* Rules Engine – re-use compliance checks.
* Dashboard – surface PR review stats.
* Kafka `pr.review.completed` for future ML models.

---

## Governance & Tracking

| Ritual | Frequency | Artifact |
|--------|-----------|----------|
| Roadmap review | bi-weekly | This doc (update status) |
| Demo / stakeholder sync | end of each phase | Recorded demo |
| Retrospective | after each capability | Retro notes |

Jira epics already created: `B2B-QUALITY-DASH`, `B2B-RULES`, `B2B-GH-INTEGRATION`.  
Owners: **BE**–@benjamin, **FE**–@frontend-lead, **Dev Ops**–@ops.

---

### Next Action (Week 1)

1. **Kick-off meeting** with all owners – align on deliverables & timelines.  
2. Create `daily_service_stats` and `hourly_service_stats` materialized views.  
3. Scaffold `quality_dashboard` controller + route (`/quality`).  
4. Draft Slack incident alert format and configure secrets in `credentials.yml.enc`.

_Stay disciplined; ship incremental value every sprint!_
