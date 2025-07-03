# frozen_string_literal: true

namespace :phantom do
  desc "Monitor and timeout stuck PhantomBuster jobs"
  task monitor: :environment do
    puts "Checking for stuck PhantomBuster jobs..."
    PhantomJobMonitorWorker.new.perform
    puts "Phantom job monitoring completed."
  end

  desc "Schedule recurring phantom job monitoring (every 5 minutes)"
  task schedule_monitor: :environment do
    # Schedule the monitor to run every 5 minutes
    # This approach ensures continuous monitoring even if individual schedules fail
    loop do
      PhantomJobMonitorWorker.perform_async
      puts "Scheduled phantom job monitor at #{Time.current}"
      sleep 300 # 5 minutes
    end
  end

  desc "Check current status of all phantom jobs"
  task status: :environment do
    pending_jobs = ServiceAuditLog.where(
      service_name: "person_profile_extraction_async",
      status: "pending"
    ).order(started_at: :desc)

    if pending_jobs.any?
      puts "\nPending PhantomBuster Jobs:"
      puts "-" * 80
      pending_jobs.each do |job|
        duration = Time.current - job.started_at
        puts "ID: #{job.id} | Company: #{job.auditable&.company_name} | Duration: #{(duration / 60).round(1)} minutes"
        puts "  Container: #{job.metadata['container_id'] || 'N/A'}"
        puts "  Started: #{job.started_at}"
        puts ""
      end
    else
      puts "No pending PhantomBuster jobs found."
    end

    # Show recently failed jobs
    failed_jobs = ServiceAuditLog.where(
      service_name: "person_profile_extraction_async",
      status: "failed"
    ).where("completed_at > ?", 24.hours.ago).order(completed_at: :desc).limit(5)

    if failed_jobs.any?
      puts "\nRecently Failed Jobs (Last 24 hours):"
      puts "-" * 80
      failed_jobs.each do |job|
        puts "ID: #{job.id} | Company: #{job.auditable&.company_name}"
        puts "  Error: #{job.error_message}"
        puts "  Failed at: #{job.completed_at}"
        puts ""
      end
    end
  end
end
