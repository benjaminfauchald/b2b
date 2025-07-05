module ApplicationHelper
  include Pagy::Frontend

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
end
