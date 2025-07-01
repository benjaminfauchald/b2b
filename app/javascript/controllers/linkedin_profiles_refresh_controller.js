import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { 
    companyId: Number,
    refreshInterval: { type: Number, default: 5000 }
  }
  
  connect() {
    console.log("LinkedIn profiles refresh controller connected for company", this.companyIdValue)
    this.startRefreshing()
  }
  
  disconnect() {
    this.stopRefreshing()
  }
  
  startRefreshing() {
    // Check if there's a pending profile extraction
    this.checkForPendingExtraction()
    
    // Set up interval to check periodically
    this.refreshTimer = setInterval(() => {
      this.checkForPendingExtraction()
    }, this.refreshIntervalValue)
  }
  
  stopRefreshing() {
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer)
    }
  }
  
  checkForPendingExtraction() {
    // Check service audit logs for pending extraction
    fetch(`/companies/${this.companyIdValue}/profile_extraction_status`, {
      headers: {
        'Accept': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      }
    })
    .then(response => response.json())
    .then(data => {
      if (data.has_pending) {
        console.log("Profile extraction is pending, will check again...")
      } else if (data.recently_completed) {
        console.log("Profile extraction completed, refreshing...")
        this.refreshProfiles()
        this.stopRefreshing() // Stop checking once completed
      } else {
        // No pending extraction, stop checking
        this.stopRefreshing()
      }
    })
    .catch(error => {
      console.error("Error checking extraction status:", error)
    })
  }
  
  refreshProfiles() {
    // Reload the LinkedIn profiles section via Turbo
    const profilesSection = document.getElementById(`company_linkedin_profiles_${this.companyIdValue}`)
    if (profilesSection) {
      fetch(`/companies/${this.companyIdValue}/linkedin_profiles`, {
        headers: {
          'Accept': 'text/vnd.turbo-stream.html',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        }
      })
      .then(response => response.text())
      .then(html => {
        Turbo.renderStreamMessage(html)
      })
      .catch(error => {
        console.error("Error refreshing profiles:", error)
      })
    }
  }
}