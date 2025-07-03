# frozen_string_literal: true

# This file would configure recurring jobs if we had sidekiq-cron installed
# For now, we'll schedule the PhantomJobMonitorWorker manually from each phantom job
# or use a rake task with cron/whenever gem

# To enable automatic monitoring every 5 minutes, add to your Gemfile:
# gem 'sidekiq-cron'
#
# Then uncomment this configuration:
#
# require 'sidekiq'
# require 'sidekiq-cron'
#
# if Sidekiq.server?
#   Sidekiq::Cron::Job.load_from_hash!({
#     'phantom_job_monitor' => {
#       'class' => 'PhantomJobMonitorWorker',
#       'cron' => '*/5 * * * *', # Every 5 minutes
#       'queue' => 'default',
#       'description' => 'Monitor and timeout stuck PhantomBuster jobs'
#     }
#   })
# end
