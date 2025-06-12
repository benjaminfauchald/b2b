json.extract! domain, :id, :domain_name, :www, :mx, :created_at, :updated_at
json.url domain_url(domain, format: :json)
