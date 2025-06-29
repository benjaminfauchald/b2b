# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Rails Server & Development Stack
- `./bin/rake dev` - **RECOMMENDED** Start full development stack (Rails + ngrok tunnel)
- `./bin/rake dev:stop` - Stop all development services
- `./bin/rake dev:status` - Check status of development services
- `./bin/rake restart` - Restart only Rails server (kills old processes and starts fresh)
- `./bin/rake kill` - Kill any Rails server running on port 3000
- `./bin/rails console` - Open Rails console
- **IMPORTANT**: Rails server ALWAYS starts on port 3000 and binds to 0.0.0.0
- `rake test:restart` - Restart Rails server for testing purposes
- **BEST PRACTICE**: Use `bundle exec rake test:restart` instead of Bash(PORT=3000 rails server &) or any other starting of rails

## API Notes

### Brreg Financial Data API
- The API returns 404 if no financial data is found for a company, which is a feature not an error
- Example working company URL with financial info: https://data.brreg.no/regnskapsregisteret/regnskap/989164155
- Example company URL without financial info (returns 404): https://data.brreg.no/regnskapsregisteret/regnskap/932968126
- The api.brreg.no API gives 404 if there is not found any financial data. It's not an error, it's a feature

## Development Best Practices
- Never use localhost for any server setup or testing use local.connectica.no
- Always touch a file before you write to avoid this error "Error: File has not been read yet. Read it first before writing to it."
- Make sure we dont start to make duplicates of files like homepage_hero_component 2.rb or /homepage_stats_component 2.r. We ALWAYS need to work on the actual file or the system will lose integrity!
- Make sure that we write any temporary files and scripts to the tmp/ folder

## Git Commit Guidelines
- When creating commits, DO NOT include the "Generated with Claude Code" or "Co-Authored-By: Claude" lines
- Keep commit messages focused on the technical changes only
- Use detailed, elaborate commit messages with the following structure:
  - Start with a concise summary line (50-72 characters)
  - Follow with a blank line
  - Include a detailed bullet list of all specific changes made
  - Explain the reasoning behind the changes and what problems they solve
  - Mention any UI/UX improvements or design system updates
  - Note any temporary changes, workarounds, or future considerations
  - End with a brief summary paragraph of what was accomplished
  - Example format:
    ```
    Improve authentication pages design and UX consistency

    - Remove duplicate OAuth buttons and "Forgot password" links from shared links partial
    - Update sign-in and create account buttons to use Flowbite primary button styling
    - Standardize dividers with uppercase text and flexbox layout  
    - Add support for custom OAuth button text (e.g., "Create account with" vs "Sign in with")
    - Ensure consistent button styling: rounded-lg, px-5 py-2.5, focus:ring-4
    - Comment out Google OAuth (keeping code for future implementation)
    - Fix dark mode color inconsistencies across all authentication components

    All the requested design improvements have been implemented to ensure consistency
    across the authentication flow and align with the Flowbite design system used
    throughout the application.
    ```