# Turbo & Hotwire Implementation Guidelines

Based on real-world debugging experience implementing toast notifications and form submissions with Turbo Streams.

## 1. Form Configuration for Turbo Stream Responses

### ✅ Correct Form Setup
```erb
<%= form_with url: your_path, 
              method: :post,
              data: { controller: "your-controller" } do |form| %>
```

### ❌ Avoid These Common Mistakes
- Don't use `local: false` - it's for Rails UJS, not Turbo
- Don't add `format: :turbo_stream` to the URL helper
- Don't use `remote: true` - that's Rails UJS syntax

## 2. Controller Response Handling

### ✅ Proper Turbo Stream Response
```ruby
respond_to do |format|
  format.turbo_stream do
    render turbo_stream: [
      turbo_stream.replace("target_id", partial: "partial_name", locals: {}),
      turbo_stream.append("container_id", partial: "notification", locals: {})
    ]
  end
  format.json do
    # Fallback for non-Turbo requests
    render json: { success: true }
  end
end
```

### Key Points:
- Always include `respond_to` block for format handling
- Request format will be `text/vnd.turbo-stream.html` for Turbo Stream requests
- Can render multiple turbo_stream actions in an array
- Always provide fallback formats (JSON/HTML)

## 3. Toast Notifications with Turbo Streams

### ❌ Problem: Appending to `body` Doesn't Always Work
Turbo may have issues appending directly to the body element.

### ✅ Solution: Use a Dedicated Container
1. Add a toast container to your layout:
```erb
<body>
  <!-- Toast notification container -->
  <div id="toast-container" class="fixed top-20 right-5 z-50"></div>
  <!-- Rest of your content -->
</body>
```

2. Append toasts to the container:
```ruby
turbo_stream.append("toast-container", 
  partial: "shared/toast_notification",
  locals: { message: "Success!", type: "success" }
)
```

3. Remove fixed positioning from individual toasts since container handles it

## 4. Debugging Turbo Stream Requests

### JavaScript Debugging
```javascript
// Add event listeners to debug Turbo submissions
element.addEventListener('turbo:before-fetch-request', (e) => {
  console.log('Request URL:', e.detail.url.toString())
  console.log('Request method:', e.detail.fetchOptions.method)
  console.log('Request body:', e.detail.fetchOptions.body)
})

element.addEventListener('turbo:before-fetch-response', async (e) => {
  console.log('Response status:', e.detail.fetchResponse.response.status)
  const responseText = await e.detail.fetchResponse.response.clone().text()
  console.log('Response body:', responseText)
})
```

### Controller Debugging
```ruby
# Log request details
Rails.logger.info "Request format: #{request.format}"
Rails.logger.info "Headers: #{request.headers['Accept']}"

# Temporary file logging for debugging
File.open(Rails.root.join('tmp', 'debug.log'), 'a') do |f|
  f.puts "Action called at #{Time.now}"
  f.puts "Params: #{params.inspect}"
end
```

## 5. Common Issues and Solutions

### Issue: Form Submits but No UI Updates
**Symptoms:**
- Form submission successful (200 response)
- No toast notifications appear
- Console shows Turbo response received

**Solutions:**
1. Check if Turbo is processing the response format
2. Verify target elements exist in DOM
3. Use dedicated containers instead of appending to body
4. Check for JavaScript errors preventing Turbo from processing

### Issue: Wrong Request Format
**Symptoms:**
- Controller receives HTML format instead of Turbo Stream
- Response returns full page instead of partial updates

**Solutions:**
1. Don't override form configuration with conflicting options
2. Let Turbo handle the request headers automatically
3. Check that Turbo is properly imported in application.js

## 6. Best Practices

### 1. Use Stimulus Controllers for Form Enhancement
```javascript
export default class extends Controller {
  connect() {
    // Initialize form behavior
    this.element.addEventListener('turbo:submit-end', this.handleSubmission.bind(this))
  }
  
  handleSubmission(event) {
    if (event.detail.success) {
      // Update UI or dispatch events
    }
  }
}
```

### 2. Structure Turbo Stream Responses
- Update data displays first (replace actions)
- Add notifications last (append actions)
- Keep responses focused and minimal

### 3. Provide User Feedback
- Always show success/error messages
- Update relevant UI sections immediately
- Use loading states during submission

### 4. Test Turbo Stream Responses
```ruby
# In your tests
assert_turbo_stream action: "replace", target: "company_stats"
assert_turbo_stream action: "append", target: "toast-container"
```

## 7. Animation and Styling

### CSS for Smooth Transitions
```css
.animate-fade-in {
  animation: fadeIn 0.3s ease-in-out;
}

@keyframes fadeIn {
  from {
    opacity: 0;
    transform: translateX(100%);
  }
  to {
    opacity: 1;
    transform: translateX(0);
  }
}
```

## 8. Checklist for Turbo Implementation

- [ ] Form uses `form_with` without Rails UJS options
- [ ] Controller responds to turbo_stream format
- [ ] Toast container exists in layout
- [ ] Turbo is imported in application.js
- [ ] Target elements have unique IDs
- [ ] Responses include user feedback
- [ ] Fallback formats are provided
- [ ] JavaScript error handling is in place

## 9. Testing Strategy

1. **Check Request Format**: Verify `request.format` is `text/vnd.turbo-stream.html`
2. **Verify Response**: Log response body to ensure correct Turbo Stream HTML
3. **DOM Updates**: Confirm target elements are updated/appended
4. **User Feedback**: Ensure notifications appear and auto-dismiss

Remember: Turbo Streams are powerful but require careful attention to DOM structure and response formatting. When in doubt, simplify and debug step by step.