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
      return uri.scheme.in?(%w[http https mailto])
    rescue URI::InvalidURIError
      return false
    end
  end
end
