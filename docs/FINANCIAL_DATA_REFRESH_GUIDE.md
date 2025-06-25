# Enhanced Financial Data Refresh System

## Overview

The financial data card has been upgraded from constant 1-second polling to an event-driven system that refreshes only when data actually changes, improving performance and user experience.

## How It Works

### 1. Event-Driven Updates
- **Real-time**: Uses ActionCable WebSockets for instant updates when financial data changes
- **Efficient**: Only refreshes when data actually changes, not constantly
- **Fallback**: Falls back to 30-second polling if WebSocket connection is lost

### 2. Components

#### Frontend (Stimulus Controller)
- `app/javascript/controllers/company_financials_controller.js`
- Subscribes to company-specific financial updates
- Handles real-time updates and fallback polling
- Updates UI indicators (status, timestamp)

#### Backend (ActionCable Channel)
- `app/channels/company_financials_channel.rb`
- Broadcasts updates when financial data changes
- Company-specific channels for targeted updates

#### Service Integration
- `CompanyFinancialsService` now broadcasts updates via ActionCable
- Triggers `CompanyFinancialsChannel.broadcast_financial_update()` on successful updates

#### Controller Action
- `companies#financial_data` provides Turbo Stream updates
- Route: `GET /companies/:id/financial_data`

## Usage

### In Views
```erb
<!-- Company show page -->
<div data-controller="company-financials" 
     data-company-financials-company-id-value="<%= @company.id %>"
     data-company-financials-fallback-interval-value="30000">
  <div id="company_financial_data_<%= @company.id %>">
    <%= render CompanyFinancialDataComponent.new(company: @company) %>
  </div>
</div>
```

### Broadcasting Updates (from Services)
```ruby
# In your service after updating financial data
CompanyFinancialsChannel.broadcast_financial_update(company, {
  status: 'success',
  changed_fields: ['operating_revenue', 'annual_result'],
  financials: { operating_revenue: 1000000, annual_result: 50000 },
  company_id: company.id
})
```

## Benefits

### Before (1-second polling)
- ❌ Constant server requests every second
- ❌ High server load and bandwidth usage
- ❌ Updates regardless of whether data changed
- ❌ Poor scaling with multiple users

### After (Event-driven)
- ✅ Updates only when data actually changes
- ✅ Real-time updates via WebSockets
- ✅ Graceful fallback to 30-second polling
- ✅ Much lower server load
- ✅ Better user experience with instant updates
- ✅ Scales better with multiple users

## Configuration

### Refresh Intervals
- **WebSocket**: Instant updates when data changes
- **Fallback polling**: 30 seconds (configurable via `data-company-financials-fallback-interval-value`)
- **Index page polling**: 30 seconds (reduced from 1 second)

### Customization
You can adjust the fallback interval by changing the data attribute:
```erb
data-company-financials-fallback-interval-value="60000"  <!-- 1 minute -->
```

## Troubleshooting

### WebSocket Connection Issues
If WebSockets aren't working, the system will automatically fall back to polling every 30 seconds and log the issue to the browser console.

### Debugging
Open browser console to see connection status and update events:
```javascript
// Shows connection status
"Connected to CompanyFinancialsChannel for company: 123"

// Shows received updates
"Received financial update: {type: 'financial_data_updated', ...}"
```

## Implementation Notes

1. **Backward Compatible**: Existing views continue to work
2. **Progressive Enhancement**: Falls back gracefully if ActionCable isn't available
3. **Targeted Updates**: Each company has its own channel to avoid unnecessary updates
4. **Error Handling**: Comprehensive error handling and logging

This system significantly improves performance while providing a better user experience with real-time updates.
