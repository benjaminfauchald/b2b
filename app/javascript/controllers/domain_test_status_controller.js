import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { 
    domainId: Number,
    testing: Boolean,
    refreshInterval: { type: Number, default: 1000 }
  }
  
  connect() {
    console.log("Domain test status controller connected for domain", this.domainIdValue)
    if (this.testingValue) {
      this.startPolling()
    }
  }
  
  disconnect() {
    this.stopPolling()
  }
  
  startPolling() {
    // Set up interval to check test status
    this.refreshTimer = setInterval(() => {
      this.checkTestStatus()
    }, this.refreshIntervalValue)
  }
  
  stopPolling() {
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer)
      this.refreshTimer = null
    }
  }
  
  checkTestStatus() {
    fetch(`/domains/${this.domainIdValue}/test_status`, {
      method: 'GET',
      credentials: 'same-origin',
      headers: {
        'Accept': 'text/vnd.turbo-stream.html',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      }
    })
    .then(response => {
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`)
      }
      return response.text()
    })
    .then(html => {
      // Log the response for debugging
      console.log("Received Turbo Stream response for domain", this.domainIdValue)
      
      // Render the Turbo Stream response
      Turbo.renderStreamMessage(html)
      
      // Force a small delay to ensure DOM is updated
      setTimeout(() => {
        // Check if we should stop polling by looking at the updated DOM
        const updatedElement = document.getElementById(`domain-test-status-${this.domainIdValue}`)
        if (updatedElement) {
          const stillTesting = updatedElement.dataset.domainTestStatusTestingValue === 'true'
          console.log("Domain", this.domainIdValue, "testing status:", stillTesting)
          
          if (!stillTesting && this.refreshTimer) {
            console.log("All tests complete, stopping polling for domain", this.domainIdValue)
            this.stopPolling()
          }
        } else {
          console.warn("Could not find updated element for domain", this.domainIdValue)
        }
      }, 100)
    })
    .catch(error => {
      console.error("Error checking domain test status:", error)
      // Only stop polling on persistent errors
      if (error.message.includes('401') || error.message.includes('403')) {
        console.error("Authentication error - stopping polling")
        this.stopPolling()
      }
    })
  }
}