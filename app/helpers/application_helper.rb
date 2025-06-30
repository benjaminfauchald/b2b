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
end
