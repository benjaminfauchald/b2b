import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "form"]
  static values = { companyId: Number }

  connect() {
    console.log("Profile extraction controller connected")
  }

  submit(event) {
    event.preventDefault()
    
    const button = this.buttonTarget
    const originalText = button.innerHTML
    
    // Disable button and show loading state
    button.disabled = true
    button.innerHTML = `
      <svg class="animate-spin -ml-1 mr-3 h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
      </svg>
      Queueing...
    `

    // Submit the form via fetch
    fetch(this.formTarget.action, {
      method: 'POST',
      headers: {
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
        'Accept': 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams(new FormData(this.formTarget))
    })
    .then(response => response.json())
    .then(data => {
      if (data.success) {
        button.innerHTML = `
          <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
          </svg>
          Queued Successfully
        `
        button.classList.remove('bg-blue-600', 'hover:bg-blue-700')
        button.classList.add('bg-green-600', 'hover:bg-green-700')
        
        // Show success message
        this.showNotification(data.message, 'success')
        
        // Reload the page after 2 seconds to show the new audit log
        setTimeout(() => {
          window.location.reload()
        }, 2000)
      } else {
        button.innerHTML = originalText
        button.disabled = false
        this.showNotification(data.message || 'An error occurred', 'error')
      }
    })
    .catch(error => {
      console.error('Error:', error)
      button.innerHTML = originalText
      button.disabled = false
      this.showNotification('Failed to queue profile extraction', 'error')
    })
  }

  showNotification(message, type = 'success') {
    const notification = document.createElement('div')
    notification.className = `fixed top-4 right-4 z-50 p-4 rounded-lg shadow-lg text-white transition-all duration-300 ${
      type === 'success' ? 'bg-green-600' : 'bg-red-600'
    }`
    notification.innerHTML = `
      <div class="flex items-center">
        ${type === 'success' 
          ? '<svg class="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path></svg>'
          : '<svg class="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path></svg>'
        }
        <span>${message}</span>
      </div>
    `
    document.body.appendChild(notification)
    
    // Remove notification after 5 seconds
    setTimeout(() => {
      notification.remove()
    }, 5000)
  }
}