import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { 
    confirmMessage: String 
  }

  connect() {
    console.log('PhantomBuster restart controller connected')
  }

  restart(event) {
    event.preventDefault()
    
    // Show confirmation dialog
    const message = this.confirmMessageValue || "Are you sure you want to restart the PhantomBuster queue?"
    
    if (!confirm(message)) {
      return
    }

    // Disable button during request
    const button = event.currentTarget
    const originalText = button.textContent
    button.disabled = true
    button.textContent = "Restarting..."

    // Make API request to restart queue
    fetch('/api/phantom_buster/restart_queue', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
      }
    })
    .then(response => response.json())
    .then(data => {
      if (data.success) {
        // Show success message
        this.showNotification('Queue restarted successfully', 'success')
        
        // Trigger status refresh for all components
        this.refreshStatusComponents()
      } else {
        // Show error message
        this.showNotification(data.error || 'Failed to restart queue', 'error')
      }
    })
    .catch(error => {
      console.error('Error restarting queue:', error)
      this.showNotification('Network error while restarting queue', 'error')
    })
    .finally(() => {
      // Re-enable button
      button.disabled = false
      button.textContent = originalText
    })
  }

  showNotification(message, type) {
    // Create temporary notification
    const notification = document.createElement('div')
    notification.className = `fixed top-4 right-4 z-50 p-4 rounded-lg shadow-lg ${
      type === 'success' 
        ? 'bg-green-500 text-white' 
        : 'bg-red-500 text-white'
    }`
    notification.textContent = message
    
    document.body.appendChild(notification)
    
    // Auto-remove after 5 seconds
    setTimeout(() => {
      if (notification.parentNode) {
        notification.parentNode.removeChild(notification)
      }
    }, 5000)
  }

  refreshStatusComponents() {
    // Find and trigger refresh for PhantomBuster status components
    const statusControllers = this.application.getControllerForElementAndIdentifier(
      document.body, 
      'phantom-buster-status'
    )
    
    // Also refresh via custom event
    document.dispatchEvent(new CustomEvent('phantom-buster:queue-restarted'))
  }

  disconnect() {
    console.log('PhantomBuster restart controller disconnected')
  }
}