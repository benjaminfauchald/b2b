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
      headers: {
        'Accept': 'text/vnd.turbo-stream.html',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      }
    })
    .then(response => {
      if (!response.ok) throw new Error('Network response was not ok')
      return response.text()
    })
    .then(html => {
      Turbo.renderStreamMessage(html)
    })
    .catch(error => {
      console.error("Error checking domain test status:", error)
      // Stop polling on error
      this.stopPolling()
    })
  }
}