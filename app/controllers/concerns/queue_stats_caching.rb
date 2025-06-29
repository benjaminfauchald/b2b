module QueueStatsCaching
  extend ActiveSupport::Concern

  private

  def get_cached_queue_stats
    Rails.cache.fetch("queue_stats_#{current_user.id}", expires_in: 1.second) do
      get_queue_stats
    end
  end

  # Invalidate cache when domains are queued
  def invalidate_queue_stats_cache
    Rails.cache.delete("queue_stats_#{current_user.id}")
  end
end