import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "button", "status"]
  static values = { 
    domainId: Number,
    service: String,
    refreshInterval: { type: Number, default: 10000 } // 10 seconds
  }

  connect() {
    console.log("Domain Service Queue Controller connected")
    this.setupFormSubmission()
    this.startStatusPolling()
  }

  disconnect() {
    this.stopStatusPolling()
  }

  setupFormSubmission() {
    this.formTargets.forEach(form => {
      form.addEventListener('submit', this.handleFormSubmit.bind(this))
    })
  }

  async handleFormSubmit(event) {
    event.preventDefault()
    
    const form = event.target
    const button = form.querySelector('button[type="submit"]')
    const formData = new FormData(form)
    
    // Set button to loading state
    this.setButtonLoading(button, true)
    
    try {
      const response = await fetch(form.action, {
        method: 'POST',
        body: formData,
        headers: {
          'X-Requested-With': 'XMLHttpRequest',
          'Accept': 'application/json'
        }
      })
      
      const data = await response.json()
      
      if (data.success) {
        // Show success feedback
        this.showSuccessMessage(data.message)
        
        // Immediately update status to pending
        this.updateButtonToPending(button, data.service)
        
        // Start aggressive polling for status updates
        this.startAggressivePolling()
      } else {
        // Show error message
        this.showErrorMessage(data.message || 'Failed to queue domain for testing')
        
        // Reset button state
        this.setButtonLoading(button, false)
      }
    } catch (error) {
      console.error('Error submitting form:', error)
      this.showErrorMessage('Network error occurred. Please try again.')
      this.setButtonLoading(button, false)
    }
  }

  setButtonLoading(button, loading) {
    if (loading) {
      button.disabled = true
      button.innerHTML = `
        <svg class="animate-spin -ml-1 mr-3 h-4 w-4 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
        </svg>
        <span class="ml-1">Queueing...</span>
      `
    }
  }

  updateButtonToPending(button, service) {
    button.disabled = true
    button.innerHTML = `
      <svg class="animate-spin -ml-1 mr-3 h-4 w-4 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
      </svg>
      <span class="ml-1">Testing...</span>
    `
    
    // Update button classes to pending state
    button.className = button.className.replace(/bg-(blue|green|orange)-\d+/, 'bg-gray-400')
                                     .replace(/hover:bg-(blue|green|orange)-\d+/, 'hover:bg-gray-500')
  }

  startStatusPolling() {
    // Regular polling every 10 seconds
    this.pollingInterval = setInterval(() => {
      this.refreshStatus()
    }, this.refreshIntervalValue)
  }

  startAggressivePolling() {
    // More frequent polling for 2 minutes after queueing
    this.stopAggressivePolling()
    
    let pollCount = 0
    const maxPolls = 24 // 2 minutes at 5-second intervals
    
    this.aggressivePollingInterval = setInterval(() => {
      this.refreshStatus()
      pollCount++
      
      if (pollCount >= maxPolls) {
        this.stopAggressivePolling()
      }
    }, 5000) // Every 5 seconds
  }

  stopAggressivePolling() {
    if (this.aggressivePollingInterval) {
      clearInterval(this.aggressivePollingInterval)
      this.aggressivePollingInterval = null
    }
  }

  stopStatusPolling() {
    if (this.pollingInterval) {
      clearInterval(this.pollingInterval)
      this.pollingInterval = null
    }
    this.stopAggressivePolling()
  }

  async refreshStatus() {
    try {
      // Reload just the testing status card via Turbo
      const response = await fetch(window.location.href, {
        headers: {
          'Accept': 'text/html',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })
      
      if (response.ok) {
        const html = await response.text()
        const parser = new DOMParser()
        const doc = parser.parseFromString(html, 'text/html')
        
        // Find the testing status card in the new HTML
        const newStatusCard = doc.querySelector('[data-controller="domain-service-queue"]')
        
        if (newStatusCard) {
          // Replace the current status card with the new one
          this.element.innerHTML = newStatusCard.innerHTML
          
          // Reconnect event listeners
          this.setupFormSubmission()
        }
      }
    } catch (error) {
      console.error('Error refreshing status:', error)
    }
  }

  showSuccessMessage(message) {
    this.showMessage(message, 'success')
  }

  showErrorMessage(message) {
    this.showMessage(message, 'error')
  }

  showMessage(message, type) {
    // Create toast notification
    const toast = document.createElement('div')
    toast.className = `fixed top-4 right-4 z-50 p-4 rounded-lg shadow-lg transition-all duration-300 transform translate-x-full ${
      type === 'success' 
        ? 'bg-green-500 text-white' 
        : 'bg-red-500 text-white'
    }`
    
    toast.innerHTML = `
      <div class="flex items-center">
        ${type === 'success' 
          ? '<svg class="w-5 h-5 mr-2" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"></path></svg>'
          : '<svg class="w-5 h-5 mr-2" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clip-rule="evenodd"></path></svg>'
        }
        <span>${message}</span>
        <button class="ml-4 text-white hover:text-gray-200" onclick="this.parentElement.parentElement.remove()">
          <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd"></path>
          </svg>
        </button>
      </div>
    `
    
    document.body.appendChild(toast)
    
    // Animate in
    setTimeout(() => {
      toast.classList.remove('translate-x-full')
    }, 100)
    
    // Auto remove after 5 seconds
    setTimeout(() => {
      toast.classList.add('translate-x-full')
      setTimeout(() => {
        if (toast.parentElement) {
          toast.remove()
        }
      }, 300)
    }, 5000)
  }
}