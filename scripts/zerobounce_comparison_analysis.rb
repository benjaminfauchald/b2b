#!/usr/bin/env ruby
# frozen_string_literal: true

# ZeroBounce vs Our System Comparison Analysis Script
# This script analyzes differences between ZeroBounce and our hybrid email verification system
# to identify optimization opportunities and improve our system accuracy.

require File.expand_path('../config/environment', __dir__)

class ZerobounceComparisonAnalysis
  def initialize
    @people_with_data = Person.with_zerobounce_data.where.not(email_verification_status: nil)
    @total_count = @people_with_data.count
    @analysis_results = {}
  end

  def run
    puts "=" * 80
    puts "ZeroBounce vs Our System Email Verification Comparison Analysis"
    puts "=" * 80
    puts "Analysis started at: #{Time.current}"
    puts "Total people with both ZeroBounce and our verification data: #{@total_count}"
    puts

    return puts "No data available for comparison!" if @total_count.zero?

    analyze_status_agreement
    analyze_confidence_correlation
    analyze_false_positives
    analyze_false_negatives
    analyze_zerobounce_features
    generate_recommendations
    save_analysis_results

    puts "=" * 80
    puts "Analysis completed at: #{Time.current}"
    puts "Results saved to: tmp/zerobounce_analysis_#{Time.current.strftime('%Y%m%d_%H%M%S')}.json"
    puts "=" * 80
  end

  private

  def analyze_status_agreement
    puts "📊 Status Agreement Analysis"
    puts "-" * 40

    agreement_stats = {
      total: 0,
      agreements: 0,
      disagreements: 0,
      agreement_rate: 0.0
    }

    status_breakdown = Hash.new(0)
    disagreement_patterns = Hash.new(0)

    @people_with_data.find_each do |person|
      agreement_stats[:total] += 1

      our_status = person.email_verification_status
      zb_status = person.zerobounce_status

      # Map our statuses to ZeroBounce equivalents
      our_mapped = map_our_status_to_zb(our_status)
      zb_mapped = normalize_zb_status(zb_status)

      status_breakdown["#{our_mapped} vs #{zb_mapped}"] += 1

      if our_mapped == zb_mapped
        agreement_stats[:agreements] += 1
      else
        agreement_stats[:disagreements] += 1
        disagreement_patterns["Our: #{our_mapped} | ZB: #{zb_mapped}"] += 1
      end
    end

    agreement_stats[:agreement_rate] = (agreement_stats[:agreements].to_f / agreement_stats[:total] * 100).round(2)

    puts "Overall Agreement: #{agreement_stats[:agreements]}/#{agreement_stats[:total]} (#{agreement_stats[:agreement_rate]}%)"
    puts "Disagreements: #{agreement_stats[:disagreements]} (#{(100 - agreement_stats[:agreement_rate]).round(2)}%)"
    puts

    puts "Status Breakdown:"
    status_breakdown.sort_by { |_, count| -count }.each do |pattern, count|
      percentage = (count.to_f / agreement_stats[:total] * 100).round(1)
      puts "  #{pattern}: #{count} (#{percentage}%)"
    end
    puts

    puts "Top Disagreement Patterns:"
    disagreement_patterns.sort_by { |_, count| -count }.first(5).each do |pattern, count|
      percentage = (count.to_f / agreement_stats[:disagreements] * 100).round(1)
      puts "  #{pattern}: #{count} (#{percentage}%)"
    end
    puts

    @analysis_results[:status_agreement] = agreement_stats.merge(
      status_breakdown: status_breakdown,
      disagreement_patterns: disagreement_patterns
    )
  end

  def analyze_confidence_correlation
    puts "📈 Confidence Score Correlation Analysis"
    puts "-" * 40

    confidence_data = []
    correlation_stats = {
      total_compared: 0,
      high_confidence_both: 0,
      low_confidence_both: 0,
      confidence_mismatches: 0
    }

    @people_with_data.find_each do |person|
      next unless person.email_verification_confidence.present? && person.zerobounce_quality_score.present?

      our_confidence = person.email_verification_confidence
      zb_confidence = person.zerobounce_quality_score / 10.0  # Normalize to 0-1 scale

      confidence_data << {
        our: our_confidence,
        zb: zb_confidence,
        difference: (our_confidence - zb_confidence).abs,
        person_id: person.id
      }

      correlation_stats[:total_compared] += 1

      # High confidence threshold: > 0.7
      if our_confidence > 0.7 && zb_confidence > 0.7
        correlation_stats[:high_confidence_both] += 1
      elsif our_confidence < 0.4 && zb_confidence < 0.4
        correlation_stats[:low_confidence_both] += 1
      elsif (our_confidence > 0.7 && zb_confidence < 0.4) || (our_confidence < 0.4 && zb_confidence > 0.7)
        correlation_stats[:confidence_mismatches] += 1
      end
    end

    if confidence_data.any?
      avg_our_confidence = confidence_data.sum { |d| d[:our] } / confidence_data.size
      avg_zb_confidence = confidence_data.sum { |d| d[:zb] } / confidence_data.size
      avg_difference = confidence_data.sum { |d| d[:difference] } / confidence_data.size

      puts "Total comparisons: #{correlation_stats[:total_compared]}"
      puts "Average our confidence: #{avg_our_confidence.round(3)}"
      puts "Average ZB confidence: #{avg_zb_confidence.round(3)}"
      puts "Average difference: #{avg_difference.round(3)}"
      puts "High confidence agreement: #{correlation_stats[:high_confidence_both]} (#{(correlation_stats[:high_confidence_both].to_f / correlation_stats[:total_compared] * 100).round(1)}%)"
      puts "Low confidence agreement: #{correlation_stats[:low_confidence_both]} (#{(correlation_stats[:low_confidence_both].to_f / correlation_stats[:total_compared] * 100).round(1)}%)"
      puts "Confidence mismatches: #{correlation_stats[:confidence_mismatches]} (#{(correlation_stats[:confidence_mismatches].to_f / correlation_stats[:total_compared] * 100).round(1)}%)"
      puts

      # Show biggest mismatches
      biggest_mismatches = confidence_data.sort_by { |d| -d[:difference] }.first(5)
      puts "Biggest confidence mismatches:"
      biggest_mismatches.each_with_index do |data, index|
        person = Person.find(data[:person_id])
        puts "  #{index + 1}. Person #{person.id} (#{person.email}): Our #{data[:our].round(3)} vs ZB #{data[:zb].round(3)} (diff: #{data[:difference].round(3)})"
      end
    else
      puts "No confidence data available for comparison"
    end
    puts

    @analysis_results[:confidence_correlation] = correlation_stats.merge(
      confidence_data: confidence_data,
      average_our: confidence_data.any? ? confidence_data.sum { |d| d[:our] } / confidence_data.size : 0,
      average_zb: confidence_data.any? ? confidence_data.sum { |d| d[:zb] } / confidence_data.size : 0
    )
  end

  def analyze_false_positives
    puts "❌ False Positive Analysis (Our Valid, ZB Invalid)"
    puts "-" * 40

    false_positives = @people_with_data.select do |person|
      our_status = map_our_status_to_zb(person.email_verification_status)
      zb_status = normalize_zb_status(person.zerobounce_status)
      our_status == "valid" && zb_status == "invalid"
    end

    puts "False positives found: #{false_positives.count}"

    if false_positives.any?
      # Analyze patterns in false positives
      domain_patterns = Hash.new(0)
      smtp_provider_patterns = Hash.new(0)
      confidence_ranges = Hash.new(0)

      false_positives.each do |person|
        domain = person.email.split('@').last if person.email
        domain_patterns[domain] += 1 if domain

        smtp_provider_patterns[person.zerobounce_smtp_provider] += 1 if person.zerobounce_smtp_provider.present?

        confidence = person.email_verification_confidence
        if confidence
          case confidence
          when 0.0..0.3 then confidence_ranges["Low (0.0-0.3)"] += 1
          when 0.3..0.7 then confidence_ranges["Medium (0.3-0.7)"] += 1
          when 0.7..1.0 then confidence_ranges["High (0.7-1.0)"] += 1
          end
        end
      end

      puts "Top domains with false positives:"
      domain_patterns.sort_by { |_, count| -count }.first(5).each do |domain, count|
        puts "  #{domain}: #{count}"
      end
      puts

      puts "Confidence distribution of false positives:"
      confidence_ranges.each do |range, count|
        puts "  #{range}: #{count}"
      end
      puts

      # Show examples
      puts "Examples of false positives:"
      false_positives.first(3).each_with_index do |person, index|
        puts "  #{index + 1}. #{person.email} (Our: #{person.email_verification_confidence&.round(3)}, ZB: #{person.zerobounce_quality_score})"
      end
    end
    puts

    @analysis_results[:false_positives] = {
      count: false_positives.count,
      examples: false_positives.first(10).map { |p| { id: p.id, email: p.email, our_confidence: p.email_verification_confidence, zb_score: p.zerobounce_quality_score } }
    }
  end

  def analyze_false_negatives
    puts "⚠️ False Negative Analysis (Our Invalid, ZB Valid)"
    puts "-" * 40

    false_negatives = @people_with_data.select do |person|
      our_status = map_our_status_to_zb(person.email_verification_status)
      zb_status = normalize_zb_status(person.zerobounce_status)
      our_status == "invalid" && zb_status == "valid"
    end

    puts "False negatives found: #{false_negatives.count}"

    if false_negatives.any?
      # Analyze patterns
      confidence_ranges = Hash.new(0)
      domain_patterns = Hash.new(0)

      false_negatives.each do |person|
        domain = person.email.split('@').last if person.email
        domain_patterns[domain] += 1 if domain

        confidence = person.email_verification_confidence
        if confidence
          case confidence
          when 0.0..0.3 then confidence_ranges["Low (0.0-0.3)"] += 1
          when 0.3..0.7 then confidence_ranges["Medium (0.3-0.7)"] += 1
          when 0.7..1.0 then confidence_ranges["High (0.7-1.0)"] += 1
          end
        end
      end

      puts "Top domains with false negatives:"
      domain_patterns.sort_by { |_, count| -count }.first(5).each do |domain, count|
        puts "  #{domain}: #{count}"
      end
      puts

      puts "Examples of false negatives:"
      false_negatives.first(3).each_with_index do |person, index|
        puts "  #{index + 1}. #{person.email} (Our: #{person.email_verification_confidence&.round(3)}, ZB: #{person.zerobounce_quality_score})"
      end
    end
    puts

    @analysis_results[:false_negatives] = {
      count: false_negatives.count,
      examples: false_negatives.first(10).map { |p| { id: p.id, email: p.email, our_confidence: p.email_verification_confidence, zb_score: p.zerobounce_quality_score } }
    }
  end

  def analyze_zerobounce_features
    puts "🔍 ZeroBounce Feature Analysis"
    puts "-" * 40

    features = {
      free_email_detection: 0,
      mx_found: 0,
      smtp_provider_data: 0,
      did_you_mean_suggestions: 0,
      activity_data: 0,
      gender_inference: 0
    }

    @people_with_data.find_each do |person|
      features[:free_email_detection] += 1 if person.zerobounce_free_email.present?
      features[:mx_found] += 1 if person.zerobounce_mx_found.present?
      features[:smtp_provider_data] += 1 if person.zerobounce_smtp_provider.present?
      features[:did_you_mean_suggestions] += 1 if person.zerobounce_did_you_mean.present?
      features[:activity_data] += 1 if person.zerobounce_activity_data_count.to_i > 0
      features[:gender_inference] += 1 if person.zerobounce_gender.present?
    end

    puts "ZeroBounce feature coverage:"
    features.each do |feature, count|
      percentage = (count.to_f / @total_count * 100).round(1)
      puts "  #{feature.to_s.humanize}: #{count}/#{@total_count} (#{percentage}%)"
    end
    puts

    # Analyze typo suggestions
    typo_suggestions = @people_with_data.where.not(zerobounce_did_you_mean: nil)
    if typo_suggestions.any?
      puts "Typo suggestion examples:"
      typo_suggestions.limit(5).each do |person|
        puts "  #{person.email} -> #{person.zerobounce_did_you_mean}"
      end
      puts
    end

    @analysis_results[:zerobounce_features] = features
  end

  def generate_recommendations
    puts "💡 Optimization Recommendations"
    puts "-" * 40

    recommendations = []

    # Agreement rate recommendations
    agreement_rate = @analysis_results[:status_agreement][:agreement_rate]
    if agreement_rate < 85
      recommendations << "LOW AGREEMENT RATE (#{agreement_rate}%): Review status mapping logic and confidence thresholds"
    elsif agreement_rate < 95
      recommendations << "MODERATE AGREEMENT RATE (#{agreement_rate}%): Fine-tune confidence thresholds for better alignment"
    else
      recommendations << "HIGH AGREEMENT RATE (#{agreement_rate}%): System is well-aligned with ZeroBounce"
    end

    # False positive recommendations
    fp_count = @analysis_results[:false_positives][:count]
    if fp_count > @total_count * 0.1
      recommendations << "HIGH FALSE POSITIVE RATE: Consider stricter validation criteria for 'valid' status"
    end

    # False negative recommendations
    fn_count = @analysis_results[:false_negatives][:count]
    if fn_count > @total_count * 0.1
      recommendations << "HIGH FALSE NEGATIVE RATE: Consider more lenient validation criteria"
    end

    # Feature gap recommendations
    features = @analysis_results[:zerobounce_features]
    if features[:did_you_mean_suggestions] > 0
      recommendations << "FEATURE GAP: Implement typo suggestion feature (#{features[:did_you_mean_suggestions]} examples found)"
    end

    if features[:activity_data] > 0
      recommendations << "FEATURE GAP: Consider activity data integration for confidence scoring"
    end

    # Confidence correlation recommendations
    if @analysis_results[:confidence_correlation][:confidence_mismatches] > @total_count * 0.2
      recommendations << "CONFIDENCE MISMATCH: Review confidence scoring algorithm alignment"
    end

    puts "Key recommendations:"
    recommendations.each_with_index do |rec, index|
      puts "  #{index + 1}. #{rec}"
    end
    puts

    @analysis_results[:recommendations] = recommendations
  end

  def save_analysis_results
    filename = "tmp/zerobounce_analysis_#{Time.current.strftime('%Y%m%d_%H%M%S')}.json"

    @analysis_results[:metadata] = {
      analyzed_at: Time.current,
      total_people: @total_count,
      script_version: "1.0",
      analysis_scope: "ZeroBounce vs Hybrid Email Verification Comparison"
    }

    File.write(filename, JSON.pretty_generate(@analysis_results))
    puts "Analysis results saved to: #{filename}"
  end

  # Helper methods
  def map_our_status_to_zb(our_status)
    case our_status&.downcase
    when "valid" then "valid"
    when "invalid" then "invalid"
    when "suspect" then "catch-all"
    when "unverified" then "unknown"
    else "unknown"
    end
  end

  def normalize_zb_status(zb_status)
    case zb_status&.downcase
    when "valid" then "valid"
    when "invalid", "do_not_mail", "spamtrap", "abuse", "disposable" then "invalid"
    when "catch-all", "unknown", "accept_all" then "catch-all"
    else "unknown"
    end
  end
end

# Run the analysis if script is executed directly
if __FILE__ == $0
  analysis = ZerobounceComparisonAnalysis.new
  analysis.run
end
