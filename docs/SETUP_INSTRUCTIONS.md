# Setup Instructions - One-Time Setup

## 🚀 Quick Setup (5 minutes)

### Step 1: Generate SSH Key
```bash
# On your local machine
ssh-keygen -t ed25519 -f ~/.ssh/b2b_github_deploy -N ""
ssh-copy-id -i ~/.ssh/b2b_github_deploy.pub benjamin@app.connectica.no
```

### Step 2: Add GitHub Secrets
Go to: https://github.com/benjaminfauchald/b2b/settings/secrets/actions

Add these 5 secrets:
- `SSH_PRIVATE_KEY` = Content of `~/.ssh/b2b_github_deploy`
- `SSH_HOST` = `app.connectica.no`
- `SSH_USERNAME` = `benjamin`
- `RAILS_MASTER_KEY` = Content of `config/master.key`
- `DATABASE_PASSWORD` = `Charcoal2020!`

### Step 3: Test Deployment
```bash
# Switch to develop branch
git checkout develop

# Test the one-command deployment
./bin/release "1.0.0" "Initial automated deployment setup"
```

## 🎉 You're Done!

### Your Daily Workflow:
```bash
# Work on develop branch
git checkout develop
# ... make changes ...
git commit -m "Your changes"
git push origin develop

# Deploy with one command
./bin/release "1.0.1" "What you built"
```

### Check Deployment Status:
- **GitHub Actions**: https://github.com/benjaminfauchald/b2b/actions
- **Production App**: https://app.connectica.no

### Need Help?
- **Quick Reference**: [DEPLOY.md](./DEPLOY.md)
- **Troubleshooting**: [DEPLOYMENT_NOTES.md](./DEPLOYMENT_NOTES.md)

**That's it! You now have automated deployment! 🎉**
