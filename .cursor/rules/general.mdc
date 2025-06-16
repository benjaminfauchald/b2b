---
description: 
globs: 
alwaysApply: true
---
*** GENERAL RULES ***

**ALWAYS START THE RAILS SERVER ON PORT 4000 and bind to 0.0.0.0**

***IF YOU ARE FIXING TEST PLEASE CONTINUE TO FIX UNTIL YOU ARE SURE THERE IS NOTHING MORE TO FIX: DONT PROMPT USER IF YOU SHOULD CONTINUE OR NOT TO FIX; JUST DO IT***



** ALWAYS GENERATE THE FULL PLAN FIRST WITH TDD TESTS. IF YOU THINK WE SHOULD RUN OR RERUN THE TESTS TO PROCEEED TO NEXT STEP DO SO; DO NOT WAIT FOR USER INPUT TO RUN TEST TO GET TO NEXT STEP **

**NEVER ADD FIELDS OR CHANGES TO ANY TABLE OR DATABASE WITHOUT ASKING AND COMING WITH A GOOD DESIGN DECSIPON FOR THIS CHANGE AS YOUR ARGUMENT TO PROCEED**





** AFTER WE AGREE ON STRATEGY WRITE THE TEST FIRST AND CONTINUE UNTIL THE TESTS PASS GREEN **

**Please take the time to go through the entire project and understand that you're using the right version of Kafka, the right version of Karafka, and every gem version that everything is consistent, and you're not using any configuration or calls that are not the same version or have some kind of version conflict coding. **


** SERVICES RAKE TASKS CONFIG **
All services shoudl have these four rake tasks. 
1. sample  
2. queue_all
3. show_pending
4. stats

This is an example from Rails -T for "domain_a_record_testing":

domain_a_record_testing:sample           # Test A records for a sample of domains
domain_a_record_testing:queue_all        # Test A records for all domains in batches
domain_a_record_testing:show_pending     # Show domains that need A record testing
domain_a_record_testing:stats            # Show A record testing statistics


**All services should as same output format as possible, example below**

show_pending: show stats like this

Pending DNS Testing Statistics
============================================================
Total Domains: 17426
Untested Domains: 13716 (78.71%)
Recently Tested (< 24h): 3710 (21.29%)
Old Tests (> 24h): 0 (0.0%)

Sample of Untested Domains:
  se. (Created: 2025-06-13)
  0.se. (Created: 2025-06-13)
  0-0.se. (Created: 2025-06-13)
  0-0-0.se. (Created: 2025-06-13)
  0-0-1.se. (Created: 2025-06-13)

stats output format:

DNS Testing Statistics
============================================================
Domains:
  Total: 17426
  Tested: 3710 (21.29%)
  Active DNS: 3201 (86.28% of tested)
  Inactive DNS: 509

Service Audit Logs:
  Total Logs: 10088
  Successful: 3710 (36.78%)
  Failed: 5631

Performance:
  Average Duration: 4068ms
  Min Duration: 16ms
  Max Duration: 203442ms

Recent Activity (24h):
  Tests Run: 10088
  Success Rate: 36.78%


