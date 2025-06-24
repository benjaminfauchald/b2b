namespace :dev do
  desc "Start Rails server with SSL support for development"
  task :ssl do
    puts "🔒 Starting Rails server with SSL support..."
    puts "=" * 60
    puts "Access your application at:"
    puts "  https://localhost:3000"
    puts "  https://local.connectica.no:3000 (if configured in /etc/hosts)"
    puts "=" * 60
    
    # First, ensure we have a clean start
    Rake::Task["server:kill"].invoke
    
    # Generate self-signed certificate if it doesn't exist
    cert_dir = Rails.root.join('config', 'certs')
    cert_file = cert_dir.join('localhost.crt')
    key_file = cert_dir.join('localhost.key')
    
    unless cert_file.exist? && key_file.exist?
      puts "🔐 Generating self-signed SSL certificate..."
      FileUtils.mkdir_p(cert_dir)
      
      system(<<~CMD)
        openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
          -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost" \
          -keyout #{key_file} -out #{cert_file}
      CMD
    end
    
    # Start Rails with SSL
    exec("./bin/rails server -p 3000 -b 'ssl://0.0.0.0:3000?key=#{key_file}&cert=#{cert_file}'")
  end
  
  desc "Configure local domain and start server"
  task :start do
    # Run the setup script
    system("./setup_local_domain.sh")
    
    # Start the server
    Rake::Task["restart"].invoke
  end
end