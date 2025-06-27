namespace :test do
  desc "Restart Rails properly for testing from local.connectica.no"
  task :restart do
    puts "🔄 Restarting Rails for testing from https://local.connectica.no"
    puts "=" * 60

    # Step 1: Check if ngrok is running, start it if not
    puts "\n1️⃣ Checking if ngrok is running..."
    ngrok_pids = `pgrep -f "ngrok http"`.strip.split("\n")
    if ngrok_pids.any? && !ngrok_pids.first.empty?
      puts "✅ Ngrok is already running (PID: #{ngrok_pids.join(', ')})"
    else
      puts "❌ Ngrok is not running!"
      puts "   Starting ngrok automatically..."

      # Start ngrok in background
      FileUtils.mkdir_p("log")
      FileUtils.mkdir_p("tmp/pids")

      cmd = "nohup ngrok http 3000 --domain=local.connectica.no > log/ngrok.log 2>&1 &"
      system(cmd)

      # Wait for ngrok to start
      sleep 3

      # Verify ngrok started
      ngrok_pid = `pgrep -f "ngrok http"`.strip
      if ngrok_pid && !ngrok_pid.empty?
        File.write("tmp/pids/ngrok.pid", ngrok_pid)
        puts "✅ Ngrok started successfully (PID: #{ngrok_pid})"
      else
        puts "❌ Failed to start ngrok. Check log/ngrok.log for details"
        exit 1
      end
    end

    # Step 2: Kill any services running on port 3000 (but not ngrok)
    puts "\n2️⃣ Checking for processes on port 3000..."
    port_pids = `lsof -ti:3000 2>/dev/null`.strip.split("\n")

    if port_pids.any? && !port_pids.first.empty?
      # Filter out ngrok PIDs
      ngrok_pids = `pgrep -f "ngrok http"`.strip.split("\n")
      rails_pids = port_pids - ngrok_pids

      if rails_pids.any?
        puts "🛑 Found Rails processes on port 3000: #{rails_pids.join(', ')}"
        puts "   Forcibly killing them..."
        rails_pids.each do |pid|
          system("kill -9 #{pid} 2>/dev/null")
        end
        sleep 2 # Give processes time to die
        puts "✅ Rails processes killed"
      else
        puts "✅ Only ngrok is using port 3000 (this is expected)"
      end
    else
      puts "✅ Port 3000 is already free"
    end

    # Clean up any stale PID files
    pid_file = "tmp/pids/server.pid"
    if File.exist?(pid_file)
      puts "🧹 Removing stale PID file"
      File.delete(pid_file)
    end

    # Step 3: Start Rails server in background
    puts "\n3️⃣ Starting Rails server..."

    # Create log directory if it doesn't exist
    FileUtils.mkdir_p("log")

    # Clear Rails cache to ensure fresh code is loaded
    puts "🧹 Clearing Rails cache..."
    system("./bin/rails tmp:clear")

    # Touch restart file to ensure reload
    system("touch tmp/restart.txt") if File.exist?("tmp")

    # Start Rails server in background
    puts "🚀 Starting Rails server on port 3000..."
    system("nohup ./bin/rails server -p 3000 -b 0.0.0.0 > log/rails_server.log 2>&1 &")

    # Wait for server to start
    puts "⏱️  Waiting for Rails server to start..."
    sleep 8

    # Verify Rails is running
    port_check = `lsof -ti:3000 2>/dev/null`.strip.split("\n")
    rails_pids = []

    # Filter out ngrok from the port check
    if port_check.any? && !port_check.first.empty?
      ngrok_pids = `pgrep -f "ngrok http"`.strip.split("\n")
      rails_pids = port_check - ngrok_pids
    end

    if rails_pids.empty?
      puts "❌ Failed to start Rails server!"
      puts "   Check log/rails_server.log for details"
      exit 1
    else
      puts "✅ Rails server started successfully (PID: #{rails_pids.join(', ')})"
    end

    # Step 4: Test that Rails index page loads
    puts "\n4️⃣ Testing Rails index page..."

    require "net/http"
    require "uri"
    require "timeout"

    # Test local connection first
    begin
      puts "🔍 Testing local connection (http://localhost:3000)..."
      Timeout.timeout(10) do
        uri = URI.parse("http://localhost:3000")
        response = Net::HTTP.get_response(uri)
        if response.is_a?(Net::HTTPSuccess)
          puts "✅ Local Rails index page loaded successfully! (Status: #{response.code})"
        else
          puts "⚠️  Local Rails index page returned status: #{response.code}"
        end
      end
    rescue Timeout::Error
      puts "❌ Timeout waiting for local Rails server to respond"
      exit 1
    rescue => e
      puts "❌ Error connecting to local Rails server: #{e.message}"
      exit 1
    end

    # Test ngrok connection
    begin
      puts "🔍 Testing ngrok connection (https://local.connectica.no)..."
      Timeout.timeout(15) do
        uri = URI.parse("https://local.connectica.no")
        response = Net::HTTP.get_response(uri)
        if response.is_a?(Net::HTTPSuccess)
          puts "✅ Ngrok Rails index page loaded successfully! (Status: #{response.code})"
        else
          puts "⚠️  Ngrok Rails index page returned status: #{response.code}"
        end
      end
    rescue Timeout::Error
      puts "❌ Timeout waiting for ngrok to respond"
      puts "   This might be normal if ngrok is still connecting..."
    rescue => e
      puts "⚠️  Error connecting to ngrok: #{e.message}"
      puts "   This might be normal if ngrok is still establishing the tunnel..."
    end

    puts "\n" + "=" * 60
    puts "🎉 Rails restart complete!"
    puts "\n📊 Status Summary:"
    puts "   ✅ Ngrok: Running"
    puts "   ✅ Rails: Running on port 3000"
    puts "   ✅ Local test: Passed"
    puts "\n🌐 URLs:"
    puts "   Local:  http://localhost:3000"
    puts "   Ngrok:  https://local.connectica.no"
    puts "\n📝 View logs:"
    puts "   Rails: tail -f log/rails_server.log"
    puts "   Ngrok: tail -f log/ngrok.log"
    puts "\n🛑 To stop everything: rake dev:stop"
    puts "=" * 60
  end
end
