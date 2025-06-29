puts "Company model attributes:"
puts Company.attribute_names.sort

puts "\nFirst company sample:"
first_company = Company.first
if first_company
  puts "ID: #{first_company.id}"
  Company.attribute_names.each do |attr|
    value = first_company.send(attr)
    puts "#{attr}: #{value}" if value.present?
  end
else
  puts "No companies found"
end

puts "\nTotal companies: #{Company.count}"
