# Installing Ruby 3.3.8 on Production Server

## Step 1: SSH into the production server
```bash
ssh benjamin@app.connectica.no
```

## Step 2: Update rbenv and ruby-build
```bash
# Update rbenv itself
cd ~/.rbenv
git pull

# Update ruby-build plugin to get latest Ruby versions
cd ~/.rbenv/plugins/ruby-build
git pull
```

## Step 3: Install Ruby 3.3.8
This will take 5-10 minutes as it compiles Ruby from source:

```bash
# Install Ruby 3.3.8
rbenv install 3.3.8
```

If you get any errors about missing dependencies, install them first:
```bash
# Install build dependencies (if needed)
sudo apt-get update
sudo apt-get install -y build-essential libssl-dev libreadline-dev zlib1g-dev \
                        libffi-dev libyaml-dev libgdbm-dev libncurses5-dev \
                        automake libtool bison pkg-config
```

## Step 4: Set Ruby version for the project
```bash
# Navigate to your project
cd ~/b2b

# Set Ruby 3.3.8 for this project
rbenv local 3.3.8

# Verify it's set correctly
ruby -v
# Should output: ruby 3.3.8...
```

## Step 5: Install bundler for the new Ruby version
```bash
# Install bundler
gem install bundler

# Rehash to make new commands available
rbenv rehash
```

## Step 6: Bundle install with the new Ruby
```bash
# Remove old bundle config
rm -rf .bundle vendor/bundle

# Install gems
bundle install
```

## Step 7: Test the installation
```bash
# Test Rails console
RAILS_ENV=production bundle exec rails console
# Type 'exit' to quit

# Test asset compilation
RAILS_ENV=production bundle exec rails assets:precompile
```

## Optional: Set as global default
If you want Ruby 3.3.8 as the system-wide default:
```bash
rbenv global 3.3.8
```

## Troubleshooting

### If rbenv install fails
1. Check available versions:
   ```bash
   rbenv install --list | grep 3.3
   ```

2. If 3.3.8 is not listed, update ruby-build again:
   ```bash
   cd ~/.rbenv/plugins/ruby-build
   git pull origin master
   ```

3. Try installing with verbose output:
   ```bash
   RUBY_CONFIGURE_OPTS="--disable-install-doc" rbenv install 3.3.8 --verbose
   ```

### If compilation fails
Install additional dependencies:
```bash
sudo apt-get install -y libgmp-dev
```

### Memory issues during compilation
If the server has limited RAM:
```bash
# Use fewer jobs during compilation
MAKE_OPTS="-j 1" rbenv install 3.3.8
```

## Verification
After installation, run:
```bash
cd ~/b2b
ruby -v              # Should show 3.3.8
bundle -v            # Should show bundler version
bundle exec ruby -v  # Should show 3.3.8
```