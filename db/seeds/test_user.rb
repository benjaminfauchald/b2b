# Create test user for development and testing
test_user = User.find_or_create_by(email: 'test@test.no') do |user|
  user.name = 'Test User'
  user.password = 'CodemyFTW2'
  user.password_confirmation = 'CodemyFTW2'
end

if test_user.persisted?
  puts "✅ Test user created/found: test@test.no"
  puts "   Admin status: #{test_user.admin?}"
else
  puts "❌ Failed to create test user: #{test_user.errors.full_messages.join(', ')}"
end

# Also create admin user if needed
admin_user = User.find_or_create_by(email: 'admin@example.com') do |user|
  user.name = 'Admin User'
  user.password = 'CodemyFTW2'
  user.password_confirmation = 'CodemyFTW2'
end

if admin_user.persisted?
  puts "✅ Admin user created/found: admin@example.com (admin: #{admin_user.admin?})"
end