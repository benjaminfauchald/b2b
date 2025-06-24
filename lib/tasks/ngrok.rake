namespace :ngrok do
  desc "Start ngrok tunnel for local.connectica.no in background"
  task :start do
    puts "🚇 Starting ngrok tunnel for local.connectica.no..."
    
    # Check if ngrok is already running
    ngrok_pids = `pgrep -f "ngrok http"`.strip.split("\n")
    if ngrok_pids.any? && !ngrok_pids.first.empty?
      puts "⚠️  Ngrok is already running (PID: #{ngrok_pids.join(', ')})"
      puts "   Run 'rake ngrok:stop' to stop it first"
      exit 1
    end
    
    # Check if Rails server is running
    if `lsof -ti:3000`.strip.empty?
      puts "⚠️  Rails server is not running on port 3000"
      puts "   Starting Rails server first..."
      system("nohup ./bin/rails server -p 3000 -b 0.0.0.0 > log/rails_server.log 2>&1 &")
      sleep 3
    end
    
    # Start ngrok in background
    puts "🚀 Starting ngrok with domain local.connectica.no..."
    
    # Create log directory if it doesn't exist
    FileUtils.mkdir_p('log')
    
    # Start ngrok with nohup
    # Using your paid ngrok plan with custom domain for OAuth2 testing
    cmd = "nohup ngrok http 3000 --domain=local.connectica.no > log/ngrok.log 2>&1 &"
    system(cmd)
    
    # Save the PID
    sleep 2
    ngrok_pid = `pgrep -f "ngrok http"`.strip
    if ngrok_pid && !ngrok_pid.empty?
      File.write('tmp/pids/ngrok.pid', ngrok_pid)
      puts "✅ Ngrok started successfully (PID: #{ngrok_pid})"
      puts "📝 Logs: tail -f log/ngrok.log"
      puts "🌐 Access your app at: https://local.connectica.no"
    else
      puts "❌ Failed to start ngrok. Check log/ngrok.log for details"
    end
  end
  
  desc "Stop ngrok tunnel"
  task :stop do
    puts "🛑 Stopping ngrok..."
    
    # Try to read PID file first
    pid_file = 'tmp/pids/ngrok.pid'
    if File.exist?(pid_file)
      pid = File.read(pid_file).strip
      system("kill -9 #{pid} 2>/dev/null")
      File.delete(pid_file)
    end
    
    # Also kill any running ngrok processes
    system("pkill -f 'ngrok http' 2>/dev/null")
    
    puts "✅ Ngrok stopped"
  end
  
  desc "Restart ngrok tunnel"
  task :restart => [:stop, :start]
  
  desc "Show ngrok status and logs"
  task :status do
    puts "📊 Ngrok Status"
    puts "=" * 50
    
    # Check if ngrok is running
    ngrok_pids = `pgrep -f "ngrok http"`.strip.split("\n")
    if ngrok_pids.any? && !ngrok_pids.first.empty?
      puts "✅ Ngrok is running (PID: #{ngrok_pids.join(', ')})"
      
      # Show recent logs
      if File.exist?('log/ngrok.log')
        puts "\n📝 Recent logs:"
        puts "-" * 50
        system("tail -n 10 log/ngrok.log")
      end
    else
      puts "❌ Ngrok is not running"
    end
    
    # Check Rails server
    rails_pids = `lsof -ti:3000`.strip
    if rails_pids && !rails_pids.empty?
      puts "\n✅ Rails server is running on port 3000"
    else
      puts "\n❌ Rails server is not running"
    end
    
    puts "\n🌐 URLs:"
    puts "   Local: http://localhost:3000"
    puts "   Ngrok: https://local.connectica.no"
  end
end

# Convenience task to start everything
desc "Start Rails server and ngrok tunnel (full stack)"
task :dev do
  puts "🚀 Starting full development stack..."
  
  # Kill any existing processes
  Rake::Task["server:kill"].invoke
  Rake::Task["ngrok:stop"].invoke
  
  # Start Rails server in background
  puts "\n1️⃣ Starting Rails server..."
  system("nohup ./bin/rails server -p 3000 -b 0.0.0.0 > log/rails_server.log 2>&1 &")
  sleep 3
  
  # Start ngrok
  puts "\n2️⃣ Starting ngrok tunnel..."
  Rake::Task["ngrok:start"].invoke
  
  puts "\n✅ Development stack is ready!"
  puts "   Local: http://localhost:3000"
  puts "   Ngrok: https://local.connectica.no"
  puts "\n📝 View logs:"
  puts "   Rails: tail -f log/rails_server.log"
  puts "   Ngrok: tail -f log/ngrok.log"
  puts "\n🛑 To stop everything: rake dev:stop"
end

namespace :dev do
  desc "Stop Rails server and ngrok tunnel"
  task :stop do
    puts "🛑 Stopping development stack..."
    Rake::Task["server:kill"].invoke
    Rake::Task["ngrok:stop"].invoke
    puts "✅ All services stopped"
  end
  
  desc "Show development stack status"
  task :status do
    Rake::Task["ngrok:status"].invoke
  end
end