import { Controller } from "@hotwired/stimulus"

// Controller for monitoring PhantomBuster processing status
export default class extends Controller {
  static targets = ["submitButton", "buttonText", "statusContainer"]
  static values = { 
    pollInterval: { type: Number, default: 3000 },
    serviceName: { type: String, default: "person_profile_extraction" }
  }

  connect() {
    console.log("PhantomBuster status controller connected")
    this.startPolling()
    
    // Listen for queue restart events
    this.refreshHandler = this.handleQueueRestart.bind(this)
    document.addEventListener('phantom-buster:queue-restarted', this.refreshHandler)
  }

  disconnect() {
    console.log("PhantomBuster status controller disconnected")
    this.stopPolling()
    
    // Remove event listener
    if (this.refreshHandler) {
      document.removeEventListener('phantom-buster:queue-restarted', this.refreshHandler)
    }
  }

  startPolling() {
    // Initial check
    this.checkStatus()
    
    // Set up interval for periodic checks
    this.pollTimer = setInterval(() => {
      this.checkStatus()
    }, this.pollIntervalValue)
  }

  stopPolling() {
    if (this.pollTimer) {
      clearInterval(this.pollTimer)
      this.pollTimer = null
    }
  }

  async checkStatus() {
    try {
      const response = await fetch('/api/phantom_buster/status', {
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        },
        credentials: 'same-origin'
      })

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }

      const data = await response.json()
      this.updateButtonState(data)
    } catch (error) {
      console.error('Error checking PhantomBuster status:', error)
      // In case of error, assume not processing
      this.updateButtonState({ is_processing: false })
    }
  }

  updateButtonState(status) {
    const button = this.submitButtonTarget
    const isProcessing = status.is_processing
    const currentCompany = status.current_company
    
    // Only update if this is the profile extraction service
    if (this.serviceNameValue !== 'person_profile_extraction') {
      return
    }

    if (isProcessing && currentCompany) {
      // Processing state
      button.disabled = true
      button.classList.add('cursor-not-allowed', 'opacity-75')
      
      // Update button text with spinner and company name
      button.innerHTML = `
        <svg class="animate-spin -ml-1 mr-3 h-5 w-5 text-white inline" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
        </svg>
        Processing ${this.truncateCompanyName(currentCompany)}
      `
      
      // Update status container if it exists
      if (this.hasStatusContainerTarget) {
        this.updateStatusContainer(status)
      }
    } else {
      // Idle state
      button.disabled = false
      button.classList.remove('cursor-not-allowed', 'opacity-75')
      
      // Reset button text
      button.innerHTML = 'Queue Processing'
      
      // Check if there are items needing service
      const countInput = document.querySelector('[data-service-queue-target="countInput"]')
      const maxAvailable = countInput ? parseInt(countInput.dataset.maxAvailable || '0') : 0
      
      if (maxAvailable === 0) {
        button.disabled = true
        button.classList.add('cursor-not-allowed', 'opacity-50')
      }
      
      // Clear status container
      if (this.hasStatusContainerTarget) {
        this.statusContainerTarget.innerHTML = ''
      }
    }

    // Update queue length display if present
    if (status.queue_length !== undefined) {
      const queueElement = document.querySelector('[data-queue-stat="phantom_queue"]')
      if (queueElement) {
        queueElement.textContent = `${status.queue_length} in queue`
      }
    }
  }

  truncateCompanyName(name) {
    // Truncate long company names to fit in button
    const maxLength = 25
    if (name.length > maxLength) {
      return name.substring(0, maxLength) + '...'
    }
    return name
  }

  updateStatusContainer(status) {
    // Optional: Update a status container with more details
    if (!this.hasStatusContainerTarget) return
    
    let html = ''
    if (status.current_job_duration) {
      const minutes = Math.floor(status.current_job_duration / 60)
      const seconds = status.current_job_duration % 60
      html += `<p class="text-xs text-gray-600 dark:text-gray-400 mt-1">Processing for ${minutes}m ${seconds}s</p>`
    }
    
    if (status.estimated_completion) {
      const completion = new Date(status.estimated_completion)
      const remaining = Math.max(0, Math.floor((completion - new Date()) / 1000))
      const remainingMinutes = Math.floor(remaining / 60)
      const remainingSeconds = remaining % 60
      if (remaining > 0) {
        html += `<p class="text-xs text-gray-600 dark:text-gray-400">Est. ${remainingMinutes}m ${remainingSeconds}s remaining</p>`
      }
    }
    
    this.statusContainerTarget.innerHTML = html
  }

  handleQueueRestart(event) {
    console.log("Queue restart event received, checking status immediately")
    // Immediately check status after queue restart
    this.checkStatus()
  }
}