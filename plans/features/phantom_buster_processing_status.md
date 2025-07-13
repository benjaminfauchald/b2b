# PhantomBuster Processing Status Feature Plan

## Overview
Implement real-time PhantomBuster processing status display that updates the "Queue Processing" button to show current processing status with company name and disable/enable appropriately.

## Requirements
1. Check PhantomBuster processing status every 3 seconds via API
2. When processing:
   - Change button text from "Queue Processing" to "Processing {company_name}"
   - Disable the button
3. When not processing:
   - Change button text back to "Queue Processing"
   - Enable the button
4. Use Hotwire/Stimulus for real-time updates without page refresh

## Technical Approach

### 1. API Endpoint
Create a new endpoint that returns current PhantomBuster processing status:
- `GET /api/phantom_buster/status`
- Returns:
  ```json
  {
    "is_processing": true,
    "current_company": "VING NORGE AS",
    "queue_length": 5,
    "current_job_duration": 120,
    "estimated_completion": "2025-01-13T18:15:00Z"
  }
  ```

### 2. Update PersonServiceQueueButtonComponent
- Add a new turbo-frame for the button itself
- Add data attributes for Stimulus controller
- Keep existing structure but wrap button in updatable frame

### 3. Create New Stimulus Controller: phantom_buster_status_controller.js
- Poll API every 3 seconds using setInterval
- Update button text and state based on response
- Handle connection/disconnection properly
- Clean up interval on disconnect

### 4. Modify Existing service_queue_controller.js
- Work alongside the new status controller
- Ensure form submission still works correctly
- Coordinate state updates between controllers

### 5. Backend Service Updates
- Create `Api::PhantomBusterController` with status action
- Use existing `PhantomBusterSequentialQueue.queue_status` method
- Format response with company name from current job

### 6. Routes
- Add new API route: `get 'api/phantom_buster/status'`
- Ensure proper authentication

## Implementation Steps

1. **Create API Controller and Route**
   - `app/controllers/api/phantom_buster_controller.rb`
   - Add route to `config/routes.rb`

2. **Create Stimulus Controller**
   - `app/javascript/controllers/phantom_buster_status_controller.js`
   - Handle polling, updates, and cleanup

3. **Update ViewComponent**
   - Modify `person_service_queue_button_component.html.erb`
   - Add data attributes for new controller
   - Wrap button in identifiable element

4. **Add Tests**
   - API endpoint tests
   - Stimulus controller tests (if applicable)
   - Integration tests for button state changes

5. **Update CSS/Styling**
   - Ensure disabled state is visually distinct
   - Keep consistent with Flowbite design system

## UI/UX Considerations

### Button States
1. **Idle State**
   - Text: "Queue Processing"
   - Style: Blue primary button (current)
   - Enabled

2. **Processing State**
   - Text: "Processing {Company Name}"
   - Style: Blue with loading spinner
   - Disabled
   - Optional: Show progress indicator

3. **Error State**
   - Keep current state
   - Show toast notification for errors

### Visual Feedback
- Smooth transitions between states
- Loading spinner during processing
- Preserve batch size input functionality
- Keep completion percentage display updated

## Testing Strategy

1. **Unit Tests**
   - API endpoint returns correct status
   - PhantomBusterSequentialQueue integration
   - JSON response formatting

2. **Integration Tests**
   - Button state changes based on queue status
   - Polling mechanism works correctly
   - Form submission still functions

3. **Manual Testing**
   - Queue multiple companies
   - Verify button updates in real-time
   - Test error scenarios
   - Verify cleanup on page navigation

## Security Considerations
- Ensure API endpoint requires authentication
- Don't expose sensitive PhantomBuster data
- Rate limit API endpoint to prevent abuse

## Performance Considerations
- 3-second polling interval is reasonable
- Clean up intervals on page navigation
- Consider using ActionCable for real-time updates (future enhancement)

## Future Enhancements
- Show queue position for multiple companies
- Display estimated time remaining
- Add progress bar for current job
- WebSocket/ActionCable for instant updates
- Show history of recent completions