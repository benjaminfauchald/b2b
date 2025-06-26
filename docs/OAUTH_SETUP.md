# OAuth Setup Guide

This document provides instructions for setting up OAuth authentication with Google and GitHub for the b2b application.

## Current Status

### GitHub OAuth ✅ Working
- GitHub OAuth is properly configured and working
- Successfully redirects to GitHub for authentication
- Callback handling is implemented and functional

### Google OAuth ❌ Needs Configuration
- Google OAuth returns "invalid_client" error (401)
- Requires updating OAuth application configuration in Google Cloud Console

## OAuth Implementation Details

### Components
- **OAuth Button Component**: Reusable button component for OAuth providers
- **SSO Login Component**: Main component that renders OAuth login options
- **Omniauth Callbacks Controller**: Handles OAuth callbacks from providers
- **User Model**: Includes OAuth user creation and management logic

### Features Implemented
- User creation from OAuth data
- Account linking (connects OAuth to existing email accounts)
- Secure password generation for OAuth users
- Provider-specific user handling
- Error handling and fallback flows

## Required Configuration

### Google OAuth Setup

To fix the Google OAuth integration:

1. **Go to Google Cloud Console**
   - Visit: https://console.cloud.google.com/
   - Select your project or create a new one

2. **Enable Google+ API**
   - Navigate to "APIs & Services" > "Library"
   - Search for "Google+ API" and enable it

3. **Configure OAuth 2.0 Credentials**
   - Go to "APIs & Services" > "Credentials"
   - Find your OAuth 2.0 Client ID or create a new one
   - Add authorized redirect URIs:
     ```
     https://1eed-125-25-38-184.ngrok-free.app/users/auth/google_oauth2/callback
     ```
   - For production, add your production domain callback URL

4. **Environment Variables**
   - Ensure `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` are set
   - These should match the credentials from Google Cloud Console

### GitHub OAuth Setup

GitHub OAuth is already working, but for reference:

1. **GitHub OAuth App Settings**
   - Go to GitHub Settings > Developer settings > OAuth Apps
   - Set Authorization callback URL to:
     ```
     https://1eed-125-25-38-184.ngrok-free.app/users/auth/github/callback
     ```

2. **Environment Variables**
   - `GITHUB_CLIENT_ID` and `GITHUB_CLIENT_SECRET` are properly configured

## Getting ngrok URL Programmatically

For development with changing ngrok URLs:

```bash
# Get current ngrok URL
curl -s localhost:4040/api/tunnels | jq -r '.tunnels[0].public_url'

# Get OAuth callback URL
echo "$(curl -s localhost:4040/api/tunnels | jq -r '.tunnels[0].public_url')/users/auth/google_oauth2/callback"
```

## Testing OAuth Flow

1. **GitHub OAuth** (Working):
   - Visit `/users/sign_in`
   - Click "Continue with GitHub"
   - Should redirect to GitHub login
   - After authentication, redirects back to application

2. **Google OAuth** (Needs Setup):
   - Visit `/users/sign_in`
   - Click "Sign in with GoogleOauth2"
   - Currently shows "invalid_client" error
   - Will work after proper Google Cloud Console configuration

## User Flow

1. User clicks OAuth login button
2. Redirected to OAuth provider (Google/GitHub)
3. User authenticates with provider
4. Provider redirects back to `/users/auth/{provider}/callback`
5. `OmniauthCallbacksController` handles the callback
6. `User.from_omniauth` creates or finds user account
7. User is signed in and redirected to dashboard

## Security Features

- CSRF protection enabled for OAuth flows
- Secure random password generation for OAuth users
- Account linking prevents duplicate accounts
- Proper error handling and user feedback
- Session management through Devise

## Next Steps

1. Update Google OAuth application redirect URI in Google Cloud Console
2. Test Google OAuth flow end-to-end
3. Consider adding more OAuth providers if needed
4. Implement user profile management for OAuth users