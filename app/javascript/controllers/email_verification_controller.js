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
    .then(response => {
      if (!response.ok) {
        throw new Error('Network response was not ok')
      }
      return response.json()
    })
    .then(data => {
      console.log('Verification response:', data)
      
      if (data.success) {
        // Show detailed success message with status
        const statusText = data.status === 'valid' ? 'Valid' : data.status
        const confidenceText = data.confidence ? ` (${Math.round(data.confidence * 100)}% confidence)` : ''
        this.showNotification(`Email verified: ${statusText}${confidenceText}`, 'success')
        
        // Reload the page to show updated status
        setTimeout(() => {
          window.location.reload()
        }, 1500)
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
    console.log(`Showing notification: ${message} (${type})`)
    
    // Remove any existing notifications
    const existingNotifications = document.querySelectorAll('.email-verification-notification')
    existingNotifications.forEach(n => n.remove())
    
    // Create notification element
    const notification = document.createElement('div')
    notification.className = `email-verification-notification fixed top-4 right-4 z-50 px-6 py-3 rounded-lg shadow-lg text-white transition-all duration-300 ${
      type === 'success' ? 'bg-green-500' : 'bg-red-500'
    }`
    notification.style.minWidth = '250px'
    notification.innerHTML = `
      <div class="flex items-center">
        ${type === 'success' ? 
          '<svg class="w-5 h-5 mr-2" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"></path></svg>' :
          '<svg class="w-5 h-5 mr-2" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"></path></svg>'
        }
        <span>${message}</span>
      </div>
    `
    
    // Add to body
    document.body.appendChild(notification)
    
    // Animate in
    setTimeout(() => {
      notification.style.transform = 'translateX(0)'
    }, 10)
    
    // Remove after 3 seconds
    setTimeout(() => {
      notification.style.opacity = '0'
      setTimeout(() => notification.remove(), 300)
    }, 3000)
  }
}