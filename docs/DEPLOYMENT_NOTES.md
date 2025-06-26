# Deployment Notes & Server Details

## 🗺️ Production Server Details

| Setting | Value |
|---------|-------|
| **Host** | app.connectica.no |
| **Username** | benjamin |
| **SSH Port** | 22 |
| **App Path** | /home/benjamin/b2b |
| **Database** | PostgreSQL (same server) |
| **Web Server** | Nginx + Puma |
| **Background Jobs** | Sidekiq |

---

## 🔑 GitHub Secrets Setup (One-Time Only)

### 1. Generate SSH Deploy Key
```bash
# On your local machine
ssh-keygen -t ed25519 -f ~/.ssh/b2b_github_deploy -N ""

# Copy public key to server
ssh-copy-id -i ~/.ssh/b2b_github_deploy.pub benjamin@app.connectica.no

# Test connection
ssh -i ~/.ssh/b2b_github_deploy benjamin@app.connectica.no
```

### 2. Add Secrets to GitHub Repository
Go to: https://github.com/benjaminfauchald/b2b/settings/secrets/actions

| Secret Name | Value | How to Get |
|-------------|-------|------------|
| `SSH_PRIVATE_KEY` | Content of `~/.ssh/b2b_github_deploy` | `cat ~/.ssh/b2b_github_deploy` |
| `SSH_HOST` | `app.connectica.no` | From .deploy file |
| `SSH_USERNAME` | `benjamin` | From .deploy file |
| `RAILS_MASTER_KEY` | Rails master key | `cat config/master.key` |
| `DATABASE_PASSWORD` | `Charcoal2020!` | From .deploy file |

### 3. Verify SSH Key Works
```bash
# Test from your local machine
ssh -i ~/.ssh/b2b_github_deploy benjamin@app.connectica.no "echo 'SSH key works!'"
```

---

## 🛠️ Production Server Setup (One-Time Only)

### Initial Server Setup
```bash
# SSH to production server
ssh benjamin@app.connectica.no

# Ensure proper ownership
sudo chown -R benjamin:benjamin /home/benjamin/b2b
cd /home/benjamin/b2b

# Setup production environment
echo "RAILS_ENV=production" > .env
echo "DATABASE_PASSWORD=Charcoal2020!" >> .env
echo "RAILS_MASTER_KEY=$(cat config/master.key)" >> .env

# Install gems for production
bundle install --deployment --without development test

# Setup database (if first time)
RAILS_ENV=production bundle exec rails db:create
RAILS_ENV=production bundle exec rails db:migrate

# Precompile assets
RAILS_ENV=production bundle exec rails assets:precompile

# Start services
sudo systemctl enable puma
sudo systemctl enable sidekiq
sudo systemctl start puma
sudo systemctl start sidekiq
```

---

## 🔄 Service Management

### Check Service Status
```bash
# Check all services
sudo systemctl status puma
sudo systemctl status sidekiq
sudo systemctl status nginx

# Check logs
sudo journalctl -f -u puma
sudo journalctl -f -u sidekiq
tail -f /home/benjamin/b2b/log/production.log
```

### Restart Services Manually
```bash
sudo systemctl restart puma
sudo systemctl restart sidekiq
sudo systemctl reload nginx
```

### Service Configuration Files
- Puma: `/etc/systemd/system/puma.service`
- Sidekiq: `/etc/systemd/system/sidekiq.service`
- Nginx: `/etc/nginx/sites-available/b2b`

---

## 📊 Monitoring & Health Checks

### Application Health
```bash
# Check if app is responding
curl -I https://app.connectica.no

# Check database connectivity
RAILS_ENV=production bundle exec rails runner "puts ActiveRecord::Base.connection.active?"

# Check background jobs
RAILS_ENV=production bundle exec rails runner "puts Sidekiq::Queue.new.size"
```

### Log Locations
- **Rails logs**: `/home/benjamin/b2b/log/production.log`
- **Puma logs**: `journalctl -u puma`
- **Sidekiq logs**: `journalctl -u sidekiq`
- **Nginx logs**: `/var/log/nginx/access.log` & `/var/log/nginx/error.log`

---

## 🚑 Troubleshooting Common Issues

### Deployment Fails
1. **Check GitHub Actions**: https://github.com/benjaminfauchald/b2b/actions
2. **SSH connection issues**:
   ```bash
   # Test SSH manually
   ssh benjamin@app.connectica.no
   ```
3. **Permission issues**:
   ```bash
   sudo chown -R benjamin:benjamin /home/benjamin/b2b
   ```

### Services Won't Start
1. **Check systemd status**:
   ```bash
   sudo systemctl status puma
   sudo journalctl -u puma --since "1 hour ago"
   ```
2. **Check file permissions**:
   ```bash
   ls -la /home/benjamin/b2b
   ```
3. **Check environment variables**:
   ```bash
   cat /home/benjamin/b2b/.env
   ```

### Database Issues
1. **Connection problems**:
   ```bash
   sudo -u postgres psql -c "\l"
   ```
2. **Migration failures**:
   ```bash
   RAILS_ENV=production bundle exec rails db:migrate:status
   ```

### Asset Problems
1. **Recompile assets**:
   ```bash
   cd /home/benjamin/b2b
   RAILS_ENV=production bundle exec rails assets:clobber
   RAILS_ENV=production bundle exec rails assets:precompile
   ```

---

## 📝 Deployment History

### View Recent Deployments
```bash
# Check git log
cd /home/benjamin/b2b
git log --oneline -10

# Check GitHub releases
# https://github.com/benjaminfauchald/b2b/releases

# Check deployment logs
# https://github.com/benjaminfauchald/b2b/actions
```

### Manual Rollback (Emergency)
```bash
# Find previous version
git tag --sort=-version:refname | head -5

# Checkout previous version
git checkout v1.2.2

# Deploy manually
bundle install --deployment
RAILS_ENV=production bundle exec rails db:migrate
RAILS_ENV=production bundle exec rails assets:precompile
sudo systemctl restart puma sidekiq
```

---

## 📞 Contact & Support

### Quick Links
- **Production App**: https://app.connectica.no
- **GitHub Repository**: https://github.com/benjaminfauchald/b2b
- **GitHub Actions**: https://github.com/benjaminfauchald/b2b/actions
- **Deployment Guide**: [DEPLOY.md](./DEPLOY.md)

### Emergency Contacts
- **Server Provider**: [Your hosting provider]
- **Domain Provider**: [Your domain registrar]
- **Database Backup**: Check `/home/benjamin/b2b/backups/`

---

**Remember**: Most issues are solved by restarting services or checking logs! 🔧
