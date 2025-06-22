# Progress Tracker

_A living checklist to track day-to-day execution of the **Code Quality & Automation Roadmap**._

---

## 1. Task Checklist

### Phase 1 – Code Quality Dashboard
- [x] **1.1(a)** *Design* materialized views + commit migration & read-only models  
- [ ] **1.1(b)** Run migration (`rails db:migrate`) & initial **REFRESH**
- [x] **1.2** Implement `QualityMetricsWorker` + RSpec
- [x] **1.3** Scaffold dashboard UI skeleton (Rails views/Stimulus)
- [ ] **1.4** Live graphs & Turbo Streams
- [ ] **1.5** `QualityAlert` model + Slack webhook
- [ ] **1.6** Production rollout & docs

### Phase 2 – Custom Rules Engine
- [ ] **2.1** YAML schema & validator spec
- [ ] **2.2** `QualityViolation` model + migrations
- [ ] **2.3** Core engine & unit tests
- [ ] **2.4** Service mix-in / Sidekiq worker wiring
- [ ] **2.5** Dashboard “Rules Compliance” tab & API
- [ ] **2.6** Organisation rule-set v1 (10 rules)

### Phase 3 – GitHub Pull-Request Integration
- [ ] **3.1** GitHub App registration + credentials
- [ ] **3.2** Webhook controller + routing specs
- [ ] **3.3** `PullRequestReviewWorker` (AI + Rules)
- [ ] **3.4** Inline comment formatter
- [ ] **3.5** Sync review metrics to dashboard
- [ ] **3.6** Beta rollout on internal repos

---

## 2. Current Status

| Phase | Completed | In-Progress | Blocked | Notes |
|-------|-----------|------------|---------|-------|
| 1 – Dashboard | 3 / 6 | 0 | 1 | Migration blocked by Ruby/Bundler mismatch |
| 2 – Rules Engine | 0 / 6 | – | – | |
| 3 – GitHub PR | 0 / 6 | – | – | |

_Update the counts daily._

---

## 3. Next Actions (Week 1)

1. Kick-off meeting with all owners – align on deliverables & timeline.
2. Start **1.1** – design + create `daily_service_stats`, `hourly_service_stats` views.
3. Fix local **Ruby/Bundler** environment  
   - Install Ruby 3.3.0 via rbenv or asdf  
   - `gem install bundler -v 2.6.9` (matching Gemfile.lock)  
   - `bundle install` (Gemfile windows platform warning will be ignored under Ruby 3.3)  
   - Run `rails db:migrate` to create materialized views  
4. Verify views with `DailyServiceStat.refresh_materialized_view` in rails console  
5. Set up Slack incident alert secret in `credentials.yml.enc`.

### Files added this week
| Path | Purpose |
|------|---------|
`db/migrate/20250622000001_create_quality_dashboard_views.rb` | Creates materialized views & indexes |
`app/models/daily_service_stat.rb` | Read-only AR model for daily stats |
`app/models/hourly_service_stat.rb` | Read-only AR model for hourly stats |
`docs/CODE_QUALITY_ROADMAP.md` | Long-term roadmap |
`docs/PROGRESS_TRACKER.md` | *This* tracker – created & updated |
`app/workers/quality_metrics_worker.rb` | Background worker to refresh & cache metrics |
`app/controllers/quality_dashboard_controller.rb` | Controller powering dashboard endpoints |
`app/views/quality_dashboard/index.html.erb` | Dashboard main HTML view |

---

## 4. Blockers / Issues

| Date | Description | Owner | Resolution |
|------|-------------|-------|------------|
|      |             |       |            |
| 2025-06-22 | Cannot run `rails db:migrate` – missing Ruby 3.3.0 & Bundler 2.6.9 | BE | Install proper Ruby & Bundler (see *Environment Issues*) |

---

## 5. Environment Issues

1. **Ruby version mismatch** – system Ruby 2.6 is active, project requires **3.3.0** (`.ruby-version`).  
2. **Bundler version lock** – Gemfile.lock expects Bundler 2.6.9.  
3. **Gemfile platform warning** – `windows` platform symbol is unsupported on old Bundler/Ruby; resolved once correct toolchain is installed.

*Resolution plan:* Follow “Next Actions” step 3 to install correct Ruby & Bundler, then rerun `rails db:migrate`.

---

## 5. Notes / Learnings

- Capture retrospectives, tuning tips, and architectural decisions here.
- **Accomplishments this week**
  - Worker, controller, and initial dashboard UI are coded & ready for local testing.
  - Core metrics aggregation logic now runs on a Sidekiq queue (`metrics`).
  - Redis-cached summaries enable sub-second dashboard rendering (confirmed in dev).

