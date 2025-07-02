# frozen_string_literal: true

class CompanyLinkedinProfilesComponent < ViewComponent::Base
  include ActionView::Helpers::NumberHelper

  def initialize(company:)
    @company = company
    @people = company.people.order(created_at: :desc)
  end

  private

  attr_reader :company, :people

  def has_profiles?
    people.any?
  end

  def profile_count
    people.count
  end

  def email_count
    people.where.not(email: [ nil, "" ]).count
  end

  def phone_count
    people.where.not(phone: [ nil, "" ]).count
  end

  def summary_stats
    return nil unless has_profiles?

    {
      people: profile_count,
      emails: email_count,
      phones: phone_count
    }
  end

  def grouped_by_title
    # Group people by their role level for better organization
    executives = people.select { |p| executive?(p) }
    managers = people.select { |p| manager?(p) && !executive?(p) }
    others = people.select { |p| !executive?(p) && !manager?(p) }

    {
      "Executives" => executives,
      "Management" => managers,
      "Other Roles" => others
    }.reject { |_, group| group.empty? }
  end

  def executive?(person)
    return false unless person.title.present?
    title = person.title.downcase
    title.include?("ceo") || title.include?("cto") || title.include?("cfo") ||
    title.include?("chief") || title.include?("president") ||
    title.include?("executive") || title.include?("vp")
  end

  def manager?(person)
    return false unless person.title.present?
    title = person.title.downcase
    title.include?("director") || title.include?("manager") ||
    title.include?("head") || title.include?("lead")
  end

  def last_extraction_date
    latest_log = company.service_audit_logs
      .where(service_name: "person_profile_extraction", status: "success")
      .order(completed_at: :desc)
      .first

    latest_log&.completed_at
  end

  def extraction_in_progress?
    company.service_audit_logs
      .where(service_name: "person_profile_extraction", status: "pending")
      .where("created_at > ?", 10.minutes.ago)
      .exists?
  end

  def card_classes
    "bg-white border border-gray-200 rounded-lg shadow-sm dark:bg-gray-800 dark:border-gray-700"
  end

  def heading_classes
    "mb-4 text-lg font-semibold text-gray-900 dark:text-white"
  end

  def subheading_classes
    "mb-3 text-sm font-medium text-gray-700 dark:text-gray-300"
  end

  def text_muted_classes
    "text-sm text-gray-600 dark:text-gray-400"
  end

  def link_classes
    "font-medium text-blue-600 dark:text-blue-500 hover:underline"
  end
end
