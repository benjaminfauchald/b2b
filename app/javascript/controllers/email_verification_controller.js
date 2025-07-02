import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["status", "details", "button"]

  verify(event) {
    const personId = event.currentTarget.dataset.personId
    const button = event.currentTarget
    
    // Disable button and show loading state
    button.disabled = true
    button.innerHTML = `
      <svg class="animate-spin w-3 h-3 mr-1" fill="none" viewBox="0 0 24 24">
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
      </svg>
      Verifying...
    `
    
    // Make request to verify email
    fetch(`/people/${personId}/verify_email`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
        'Accept': 'application/json'
      }
    })
    .then(response => response.json())
    .then(data => {
      if (data.success) {
        // Reload the component or update the UI
        if (data.html) {
          // Replace the entire component HTML
          this.element.outerHTML = data.html
        } else {
          // Show success message
          this.showNotification('Email verification completed', 'success')
          // Reload page after short delay
          setTimeout(() => window.location.reload(), 1500)
        }
      } else {
        this.showNotification(data.error || 'Verification failed', 'error')
        // Re-enable button
        button.disabled = false
        button.innerHTML = `
          <svg class="w-3 h-3 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
          </svg>
          Verify
        `
      }
    })
    .catch(error => {
      console.error('Email verification error:', error)
      this.showNotification('An error occurred', 'error')
      // Re-enable button
      button.disabled = false
      button.innerHTML = `
        <svg class="w-3 h-3 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
        </svg>
        Verify
      `
    })
  }

  toggleDetails() {
    if (this.hasDetailsTarget) {
      this.detailsTarget.classList.toggle('hidden')
    }
  }

  showNotification(message, type) {
    // Create notification element
    const notification = document.createElement('div')
    notification.className = `fixed top-4 right-4 z-50 px-4 py-2 rounded-lg shadow-lg text-white ${
      type === 'success' ? 'bg-green-500' : 'bg-red-500'
    }`
    notification.textContent = message
    
    // Add to body
    document.body.appendChild(notification)
    
    // Remove after 3 seconds
    setTimeout(() => {
      notification.remove()
    }, 3000)
  }
}