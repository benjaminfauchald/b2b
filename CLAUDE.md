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

## API Notes

### Brreg Financial Data API
- The API returns 404 if no financial data is found for a company, which is a feature not an error
- Example working company URL with financial info: https://data.brreg.no/regnskapsregisteret/regnskap/989164155
- Example company URL without financial info (returns 404): https://data.brreg.no/regnskapsregisteret/regnskap/932968126
- The api.brreg.no API gives 404 if there is not found any financial data. It's not an error, it's a feature