puts "Top 25 Companies:"
puts "=" * 60

Company.limit(25).each_with_index do |company, index|
  puts "#{(index + 1).to_s.rjust(2)}. #{company.name}"
  puts "    Domain: #{company.domain}" if company.domain.present?
  puts "    Created: #{company.created_at.strftime('%Y-%m-%d')}"
  puts
end

puts "Total companies in database: #{Company.count}"