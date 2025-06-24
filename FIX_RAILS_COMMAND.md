# Permanent Fix for Rails Command Not Found

## Problem
The error `rbenv: rails: command not found` occurs because rbenv can't find the Rails executable in the current Ruby version's shims.

## Solution Plan

### 1. Verify Current Ruby Version
```bash
rbenv version
# Should show: 3.3.8 (or your current version)
```

### 2. Check Rails Installation
```bash
gem list rails
# Should show rails installed
```

### 3. Rehash rbenv Shims
This is usually the fix - rbenv needs to create shims for newly installed gems:
```bash
rbenv rehash
```

### 4. Alternative: Use Binstubs (Recommended)
Rails projects come with binstubs in the `bin/` directory. These are the preferred way to run Rails commands:

```bash
# Instead of: rails server
./bin/rails server

# Or add bin to your PATH for this project
export PATH="./bin:$PATH"
rails server
```

### 5. Create Alias for Convenience
Add to your shell configuration file (`~/.zshrc` or `~/.bashrc`):
```bash
# Rails alias for current project
alias rails='bundle exec rails'

# Or use binstub
alias rails='./bin/rails'
```

### 6. Permanent Project-Specific Solution
Create a `.envrc` file in the project root (if using direnv):
```bash
echo 'export PATH="./bin:$PATH"' > .envrc
direnv allow
```

### 7. Check rbenv Configuration
Ensure rbenv is properly initialized in your shell:
```bash
# Add to ~/.zshrc or ~/.bashrc if not present
eval "$(rbenv init -)"
```

## Quick Commands Reference

After applying the fix, you can use:
```bash
# Using binstub (recommended)
./bin/rails server
./bin/rails console
./bin/rails db:migrate

# Using bundle exec (always works)
bundle exec rails server
bundle exec rails console
bundle exec rails db:migrate

# After rbenv rehash or with alias
rails server
rails console
rails db:migrate
```

## Troubleshooting

If the issue persists:
1. Reinstall the rails gem: `gem install rails`
2. Run `rbenv rehash` again
3. Check shims directory: `ls $(rbenv prefix)/shims | grep rails`
4. Verify gem is installed in correct Ruby version: `rbenv which rails`