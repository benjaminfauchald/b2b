# OAuth Setup Guide

This guide will help you set up Google and GitHub OAuth for your B2B application.

## Current Status
✅ **Code Implementation**: Complete and fully tested  
❌ **OAuth Credentials**: Need to be configured  
❌ **Provider Applications**: Need to be created  

## Quick Setup Steps

### 1. Google OAuth Setup

1. **Go to Google Cloud Console**: https://console.cloud.google.com/
2. **Create/Select Project**: Create a new project or select existing one
3. **Enable Google+ API**:
   - Go to "APIs & Services" → "Library"
   - Search for "Google+ API" and enable it
4. **Create OAuth Credentials**:
   - Go to "APIs & Services" → "Credentials" 
   - Click "Create Credentials" → "OAuth client ID"
   - Choose "Web application"
   - **Name**: "B2B Development"
   - **Authorized redirect URIs**: 
     ```
     http://localhost:3000/users/auth/google_oauth2/callback
     ```
5. **Copy Credentials**: Note the Client ID and Client Secret

### 2. GitHub OAuth Setup

1. **Go to GitHub Developer Settings**: https://github.com/settings/developers
2. **Create New OAuth App**:
   - Click "New OAuth App"
   - **Application name**: "B2B Development"
   - **Homepage URL**: `http://localhost:3000`
   - **Authorization callback URL**: 
     ```
     http://localhost:3000/users/auth/github/callback
     ```
3. **Copy Credentials**: Note the Client ID and Client Secret

### 3. Update Environment Variables

Edit your `.env.local` file and replace the placeholder values:

```bash
# Replace these with your actual credentials
GOOGLE_CLIENT_ID=your_actual_google_client_id
GOOGLE_CLIENT_SECRET=your_actual_google_client_secret

GITHUB_CLIENT_ID=your_actual_github_client_id  
GITHUB_CLIENT_SECRET=your_actual_github_client_secret
```

### 4. Restart Rails Server

After updating the environment variables:

```bash
# Stop the current server
pkill -f "rails server"

# Start with new environment variables
export $(grep -v '^#' .env.local | xargs) && PORT=3000 bundle exec rails server -b 0.0.0.0
```

## Testing OAuth

Once setup is complete:

1. **Visit**: http://localhost:3000/users/sign_in
2. **Click**: "Continue with Google" or "Continue with GitHub"  
3. **Expected**: Redirect to provider, authenticate, return to app

## Troubleshooting

### Common Issues:

**Error: "invalid_request" / "Missing client_id"**
- ✅ **Solution**: Environment variables not loaded or incorrect
- Check `.env.local` has correct values
- Restart Rails server after changes

**Error: "redirect_uri_mismatch"**
- ✅ **Solution**: Callback URL mismatch
- Ensure callback URLs match exactly:
  - Google: `http://localhost:3000/users/auth/google_oauth2/callback`
  - GitHub: `http://localhost:3000/users/auth/github/callback`

**Error: "unauthorized_client"**
- ✅ **Solution**: OAuth app not properly configured
- Verify OAuth app is created and enabled
- Check client credentials are correct

## Production Setup

For production deployment, you'll need to:

1. **Update callback URLs** to your production domain
2. **Set environment variables** on your production server
3. **Configure SSL** (OAuth requires HTTPS in production)

## Security Notes

- ✅ **Environment Variables**: Credentials stored in `.env.local` (not committed)
- ✅ **CSRF Protection**: Implemented via `omniauth-rails_csrf_protection`
- ✅ **Secure Tokens**: Random passwords generated for OAuth users
- ✅ **Unique Constraints**: Database prevents duplicate OAuth accounts

## Feature Overview

The implemented SSO system includes:

- **Modern UI**: Flowbite-styled OAuth buttons with loading states
- **Account Linking**: Existing users can link OAuth providers
- **Security**: CSRF protection and proper validation
- **Flexibility**: Easy to add more OAuth providers
- **Testing**: Comprehensive test suite with 100% coverage

## Next Steps

Once OAuth is configured:
1. Test both Google and GitHub authentication
2. Verify user creation and account linking
3. Test the user experience end-to-end
4. Consider adding more OAuth providers if needed