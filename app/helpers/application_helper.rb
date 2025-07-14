module ApplicationHelper
  include Pagy::Frontend
  
  # Override pagy_nav to use our custom Flowbite-styled partial
  def pagy_nav(pagy, pagy_id: nil, link_extra: "", **vars)
    render partial: "shared/pagy_nav", locals: { pagy: pagy }
  end

  def safe_external_link(url, text = nil, options = {})
    return "" if url.blank?

    # Ensure URL starts with http:// or https://
    safe_url = url.match?(/\Ahttps?:\/\//i) ? url : "https://#{url}"

    # Validate URL format
    begin
      uri = URI.parse(safe_url)
      return "" unless uri.scheme.in?(%w[http https])
    rescue URI::InvalidURIError
      return ""
    end

    link_to(text || safe_url, safe_url, options.merge(target: "_blank", rel: "noopener"))
  end

  def url_safe?(url)
    return false if url.blank?

    # Check for javascript: protocol and other dangerous schemes
    return false if url.match?(/\A\s*(javascript|data|vbscript):/i)

    # Validate URL format
    begin
      uri = URI.parse(url)
      # Only allow http, https, and mailto protocols
      uri.scheme.in?(%w[http https mailto])
    rescue URI::InvalidURIError
      false
    end
  end

  def truncate_url(url, max_length = 50)
    return "" if url.blank?

    if url.length <= max_length
      url
    else
      # Keep the domain and truncate the path
      begin
        uri = URI.parse(url)
        domain_part = "#{uri.scheme}://#{uri.host}"
        path_part = uri.path

        # If domain itself is too long, truncate it
        if domain_part.length >= max_length - 4
          "#{domain_part[0..max_length-5]}..."
        else
          # Calculate remaining space for path
          remaining_space = max_length - domain_part.length - 3 # 3 for "..."
          if remaining_space > 0 && path_part.present?
            "#{domain_part}#{path_part[0..remaining_space-1]}..."
          else
            "#{domain_part}..."
          end
        end
      rescue URI::InvalidURIError
        # If URL parsing fails, just truncate the string
        "#{url[0..max_length-4]}..."
      end
    end
  end

  def truncate_linkedin_url(url, max_length = 35)
    return "" if url.blank?

    if url.length <= max_length
      url
    else
      # For LinkedIn URLs, show a more user-friendly truncation
      begin
        uri = URI.parse(url)
        if uri.host&.include?('linkedin')
          # Extract profile identifier from LinkedIn URLs
          if uri.path.include?('/in/')
            # Personal profile: https://linkedin.com/in/username
            profile_id = uri.path.split('/in/')[1]&.split('/')[0]
            result = "linkedin.com/in/#{profile_id}" if profile_id
            return result if result && result.length <= max_length
          elsif uri.path.include?('/company/')
            # Company profile: https://linkedin.com/company/company-name
            company_id = uri.path.split('/company/')[1]&.split('/')[0]
            result = "linkedin.com/company/#{company_id}" if company_id
            return result if result && result.length <= max_length
          elsif uri.path.include?('/sales/')
            # Sales Navigator: Show more meaningful truncation with 15 more characters
            path_parts = uri.path.split('/sales/')[1]
            if path_parts && path_parts.length > 15
              result = "linkedin.com/sales/#{path_parts[0..14]}..."
            else
              result = "linkedin.com/sales/#{path_parts || '...'}"
            end
            return result if result.length <= max_length
          end
        end
        
        # Fall back to regular truncation
        truncate_url(url, max_length)
      rescue URI::InvalidURIError
        # If URL parsing fails, just truncate the string
        "#{url[0..max_length-4]}..."
      end
    end
  end
end
