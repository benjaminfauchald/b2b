namespace :server do
  desc "Kill all processes on port 3000 and restart Rails server"
  task :restart do
    puts "🔄 Restarting Rails server..."
    
    # Kill any process using port 3000
    puts "📍 Checking for processes on port 3000..."
    port_pids = `lsof -ti:3000 2>/dev/null`.strip.split("\n")
    
    if port_pids.any? && !port_pids.first.empty?
      puts "🛑 Killing processes on port 3000: #{port_pids.join(', ')}"
      port_pids.each do |pid|
        system("kill -9 #{pid} 2>/dev/null")
      end
      sleep 1 # Give processes time to die
    else
      puts "✅ Port 3000 is already free"
    end
    
    # Clean up any stale PID files
    pid_file = Rails.root.join('tmp', 'pids', 'server.pid')
    if File.exist?(pid_file)
      puts "🧹 Removing stale PID file"
      File.delete(pid_file)
    end
    
    # Clear Rails cache to ensure fresh code is loaded
    puts "🧹 Clearing Rails cache..."
    system("./bin/rails tmp:clear")
    
    # Touch important files to ensure Rails reloads them
    puts "🔄 Touching application files to ensure reload..."
    system("touch tmp/restart.txt") if File.exist?("tmp")
    
    # Start the Rails server
    puts "🚀 Starting fresh Rails server on port 3000..."
    puts "=" * 60
    puts "Server will start now. Press Ctrl+C to stop."
    puts "=" * 60
    
    # Execute Rails server (this will take over the current process)
    exec("./bin/rails server -p 3000 -b 0.0.0.0")
  end
  
  desc "Kill all processes on port 3000"
  task :kill do
    puts "🛑 Killing processes on port 3000..."
    
    port_pids = `lsof -ti:3000 2>/dev/null`.strip.split("\n")
    
    if port_pids.any? && !port_pids.first.empty?
      puts "Found processes: #{port_pids.join(', ')}"
      port_pids.each do |pid|
        system("kill -9 #{pid} 2>/dev/null")
      end
      puts "✅ Processes killed"
    else
      puts "✅ No processes found on port 3000"
    end
    
    # Clean up PID file
    pid_file = Rails.root.join('tmp', 'pids', 'server.pid')
    if File.exist?(pid_file)
      puts "🧹 Removing stale PID file"
      File.delete(pid_file)
    end
  end
end

# Convenience aliases
desc "Restart Rails server (alias for server:restart)"
task :restart => "server:restart"

desc "Kill Rails server (alias for server:kill)"
task :kill => "server:kill"