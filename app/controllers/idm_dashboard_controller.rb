# frozen_string_literal: true

require_relative '../services/feature_memories/application_feature_memory'

class IdmDashboardController < ApplicationController
  skip_before_action :authenticate_user! # Make it accessible for developers
  
  def index
    @features = ::FeatureMemories::ApplicationFeatureMemory.all.sort_by { |f| f.feature_id }
    @stats = calculate_stats
    @search_query = params[:q]
    
    if @search_query.present?
      @features = @features.select do |feature|
        feature.feature_id.include?(@search_query.downcase) ||
        feature.feature_data.dig(:spec, :description).to_s.downcase.include?(@search_query.downcase)
      end
    end
  end
  
  def show
    @feature = ::FeatureMemories::ApplicationFeatureMemory.find(params[:id])
    if @feature
      render partial: 'feature_details', locals: { feature: @feature }
    else
      render plain: "Feature not found", status: :not_found
    end
  end
  
  private
  
  def calculate_stats
    all_features = ::FeatureMemories::ApplicationFeatureMemory.all
    
    stats = {
      total_features: all_features.size,
      by_type: {},
      by_status: { completed: 0, in_progress: 0, planning: 0, not_started: 0 },
      total_tasks: 0,
      completed_tasks: 0,
      in_progress_tasks: 0,
      pending_tasks: 0
    }
    
    all_features.each do |feature|
      # Count by type
      feature_type = feature.feature_data.dig(:spec, :requirements, :feature_type) || :unknown
      stats[:by_type][feature_type] ||= 0
      stats[:by_type][feature_type] += 1
      
      # Count by status
      status = feature.status
      if [:completed, :in_progress, :planning, :not_started].include?(status)
        stats[:by_status][status] += 1
      else
        stats[:by_status][:not_started] += 1
      end
      
      # Count tasks
      plan = feature.feature_data[:implementation_plan] || []
      stats[:total_tasks] += plan.size
      stats[:completed_tasks] += plan.count { |t| t[:status] == :completed }
      stats[:in_progress_tasks] += plan.count { |t| t[:status] == :in_progress }
      stats[:pending_tasks] += plan.count { |t| t[:status] == :pending }
    end
    
    stats[:overall_completion] = stats[:total_tasks] > 0 ? 
      (stats[:completed_tasks].to_f / stats[:total_tasks] * 100).round(1) : 0
    
    stats
  end
end