def format_number(number)
  return "" unless number
  number.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1 ').reverse
end

puts "Top 25 Companies:"
puts "=" * 80

Company.limit(25).each_with_index do |company, index|
  puts "#{(index + 1).to_s.rjust(2)}. #{company.company_name}"

  # Show key info
  info_parts = []
  info_parts << "Org: #{company.registration_number}" if company.registration_number.present?
  info_parts << "Industry: #{company.primary_industry_description}" if company.primary_industry_description.present?
  info_parts << "Revenue: #{format_number(company.operating_revenue)} NOK" if company.operating_revenue.present?
  info_parts << "Employees: #{company.employee_count}" if company.employee_count.present?
  info_parts << "Website: #{company.website}" if company.website.present?

  puts "    #{info_parts.join(' | ')}" if info_parts.any?
  puts "    #{company.postal_city}, #{company.postal_country}" if company.postal_city.present?
  puts
end

puts "Total companies in database: #{format_number(Company.count)}"
