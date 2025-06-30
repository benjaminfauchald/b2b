require "ostruct"

class PersonSocialMediaExtractionService < ApplicationService
  def initialize(person_id: nil, person: nil, **options)
    @person_id = person_id
    @person = person || (person_id ? Person.find(person_id) : nil)
    super(service_name: "person_social_media_extraction", action: "extract", **options)
  end

  def perform
    return error_result("Service is disabled") unless service_active?
    return error_result("Person not found or not provided") unless @person

    audit_service_operation(@person) do |audit_log|
      Rails.logger.info "🚀 Starting Social Media Extraction for #{@person.name}"

      # Simulate social media discovery across multiple platforms
      social_media_result = simulate_social_media_discovery(@person)

      if social_media_result[:profiles].any?
        # Update person with discovered social media profiles
        update_person_with_social_media(social_media_result)

        audit_log.add_metadata(
          platforms_found: social_media_result[:platforms_found],
          profiles: social_media_result[:profiles],
          confidence_scores: social_media_result[:profiles].map { |p| p[:confidence] }
        )

        success_result("Social media extraction completed",
                      platforms_found: social_media_result[:platforms_found],
                      profiles: social_media_result[:profiles])
      else
        audit_log.add_metadata(
          platforms_found: 0,
          reason: "No social media profiles found"
        )

        success_result("No social media profiles found for person")
      end
    end
  rescue StandardError => e
    error_result("Service error: #{e.message}")
  end

  private

  def service_active?
    config = ServiceConfiguration.find_by(service_name: "person_social_media_extraction")
    return false unless config
    config.active?
  end

  def simulate_social_media_discovery(person)
    Rails.logger.info "🔍 Searching social media platforms for #{person.name}"

    platforms = [
      { name: "Twitter", probability: 0.35, search_method: :search_twitter },
      { name: "GitHub", probability: 0.25, search_method: :search_github },
      { name: "Facebook", probability: 0.20, search_method: :search_facebook },
      { name: "Instagram", probability: 0.15, search_method: :search_instagram },
      { name: "TikTok", probability: 0.10, search_method: :search_tiktok },
      { name: "YouTube", probability: 0.08, search_method: :search_youtube }
    ]

    discovered_profiles = []

    platforms.each do |platform|
      # Simulate platform search with probability
      if rand < platform[:probability]
        profile = send(platform[:search_method], person)
        discovered_profiles << profile if profile
      end
    end

    {
      platforms_found: discovered_profiles.length,
      profiles: discovered_profiles
    }
  end

  def search_twitter(person)
    # Simulate Twitter profile discovery
    first_name = person.name.split.first&.downcase
    last_name = person.name.split.last&.downcase

    # Generate realistic Twitter handle patterns
    handles = [
      "@#{first_name}#{last_name}",
      "@#{first_name}_#{last_name}",
      "@#{first_name}#{last_name}#{rand(10..99)}",
      "@#{first_name.first}#{last_name}"
    ]

    handle = handles.sample
    confidence = rand(60..90)

    {
      platform: "Twitter",
      handle: handle,
      url: "https://twitter.com/#{handle.gsub('@', '')}",
      confidence: confidence,
      followers_count: rand(50..5000),
      verification_status: confidence > 80 ? "verified" : "unverified",
      bio: generate_twitter_bio(person),
      discovered_at: Time.current.iso8601
    }
  end

  def search_github(person)
    # Simulate GitHub profile discovery (more likely for tech professionals)
    return nil unless tech_related_person?(person)

    first_name = person.name.split.first&.downcase
    last_name = person.name.split.last&.downcase

    usernames = [
      "#{first_name}#{last_name}",
      "#{first_name}-#{last_name}",
      "#{first_name}#{last_name}#{rand(10..99)}",
      "#{first_name}.#{last_name}"
    ]

    username = usernames.sample
    confidence = rand(70..95)

    {
      platform: "GitHub",
      username: username,
      url: "https://github.com/#{username}",
      confidence: confidence,
      public_repos: rand(5..50),
      followers: rand(10..200),
      verification_status: "verified",
      bio: "Software Developer at #{person.company_name}",
      languages: [ "JavaScript", "Python", "Ruby", "Java" ].sample(rand(1..3)),
      discovered_at: Time.current.iso8601
    }
  end

  def search_facebook(person)
    # Simulate Facebook profile discovery
    confidence = rand(40..75) # Lower confidence for Facebook due to privacy settings

    {
      platform: "Facebook",
      name: person.name,
      url: "https://facebook.com/#{person.name.downcase.gsub(/\s+/, '.')}",
      confidence: confidence,
      verification_status: "unverified",
      privacy_level: [ "public", "friends_only", "private" ].sample,
      location: person.location || "Norway",
      workplace: person.company_name,
      discovered_at: Time.current.iso8601
    }
  end

  def search_instagram(person)
    # Simulate Instagram profile discovery
    first_name = person.name.split.first&.downcase
    last_name = person.name.split.last&.downcase

    usernames = [
      "#{first_name}#{last_name}",
      "#{first_name}_#{last_name}",
      "#{first_name}.#{last_name}",
      "#{first_name}#{last_name}#{rand(10..99)}"
    ]

    username = usernames.sample
    confidence = rand(50..80)

    {
      platform: "Instagram",
      username: username,
      url: "https://instagram.com/#{username}",
      confidence: confidence,
      followers: rand(100..2000),
      following: rand(50..500),
      posts_count: rand(20..200),
      verification_status: confidence > 75 ? "verified" : "unverified",
      bio: "#{person.title} | #{person.company_name}",
      discovered_at: Time.current.iso8601
    }
  end

  def search_tiktok(person)
    # Simulate TikTok profile discovery (lower probability)
    first_name = person.name.split.first&.downcase
    last_name = person.name.split.last&.downcase

    username = "#{first_name}#{last_name}#{rand(100..999)}"
    confidence = rand(30..60)

    {
      platform: "TikTok",
      username: username,
      url: "https://tiktok.com/@#{username}",
      confidence: confidence,
      followers: rand(50..1000),
      likes: rand(100..5000),
      videos_count: rand(5..50),
      verification_status: "unverified",
      discovered_at: Time.current.iso8601
    }
  end

  def search_youtube(person)
    # Simulate YouTube channel discovery
    confidence = rand(40..70)

    channel_names = [
      "#{person.name}",
      "#{person.name} - #{person.title}",
      "#{person.company_name} - #{person.name}"
    ]

    channel_name = channel_names.sample

    {
      platform: "YouTube",
      channel_name: channel_name,
      url: "https://youtube.com/c/#{channel_name.downcase.gsub(/\s+/, '')}",
      confidence: confidence,
      subscribers: rand(10..500),
      videos_count: rand(5..30),
      verification_status: confidence > 65 ? "verified" : "unverified",
      description: "Professional content by #{person.name}",
      discovered_at: Time.current.iso8601
    }
  end

  def tech_related_person?(person)
    # Check if person likely works in tech (higher GitHub probability)
    tech_keywords = [ "developer", "engineer", "programmer", "cto", "cdo", "tech", "software", "data", "ai", "ml" ]
    title = person.title&.downcase || ""
    company = person.company_name&.downcase || ""

    tech_keywords.any? { |keyword| title.include?(keyword) || company.include?(keyword) }
  end

  def generate_twitter_bio(person)
    templates = [
      "#{person.title} at #{person.company_name}",
      "#{person.title} | #{person.company_name} | #{person.location}",
      "Professional #{person.title&.downcase} based in #{person.location}",
      "Working on exciting projects at #{person.company_name}"
    ]

    templates.sample
  end

  def update_person_with_social_media(social_media_result)
    social_media_data = {
      platforms_found: social_media_result[:platforms_found],
      profiles: social_media_result[:profiles],
      extracted_at: Time.current,
      source: "mock_social_media_service",
      search_confidence: social_media_result[:profiles].map { |p| p[:confidence] }.sum / social_media_result[:profiles].length
    }

    @person.update!(
      social_media_extracted_at: Time.current,
      social_media_data: social_media_data
    )

    platforms = social_media_result[:profiles].map { |p| p[:platform] }.join(", ")
    Rails.logger.info "📱 Updated person with #{social_media_result[:platforms_found]} social media profiles: #{platforms}"
  end

  def success_result(message, data = {})
    OpenStruct.new(
      success?: true,
      message: message,
      data: data,
      error: nil
    )
  end

  def error_result(message, data = {})
    OpenStruct.new(
      success?: false,
      message: nil,
      error: message,
      data: data
    )
  end
end
