import { Controller } from "@hotwired/stimulus"
import consumer from "../channels/consumer"

export default class extends Controller {
  static values = { 
    companyId: String,
    fallbackInterval: { type: Number, default: 30000 } // 30 second fallback
  }
  
  static targets = ["container", "lastUpdated", "status"]

  connect() {
    console.log("CompanyFinancials controller connected for company:", this.companyIdValue)
    
    // Subscribe to company-specific financial updates
    this.subscription = consumer.subscriptions.create(
      { 
        channel: "CompanyFinancialsChannel", 
        company_id: this.companyIdValue 
      },
      {
        connected: () => {
          console.log("Connected to CompanyFinancialsChannel for company:", this.companyIdValue)
        },
        
        disconnected: () => {
          console.log("Disconnected from CompanyFinancialsChannel")
          // Start fallback polling if connection is lost
          this.startFallbackPolling()
        },
        
        received: (data) => {
          console.log("Received financial update:", data)
          this.handleFinancialUpdate(data)
        }
      }
    )
    
    // Listen for successful manual triggers (button clicks, etc.)
    this.element.addEventListener('financial-update-requested', this.handleManualUpdate.bind(this))
  }

  disconnect() {
    console.log("CompanyFinancials controller disconnecting")
    
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
    
    this.stopFallbackPolling()
  }
  
  // Handle updates from ActionCable
  handleFinancialUpdate(data) {
    if (data.type === 'financial_data_updated') {
      this.refreshFinancialData()
      this.updateTimestamp(data.updated_at)
      this.updateStatus(data.status || 'success')
    } else if (data.type === 'processing_started') {
      this.updateStatus('processing')
    } else if (data.type === 'processing_failed') {
      this.updateStatus('failed')
    }
  }
  
  // Handle manual update requests (like button clicks)
  handleManualUpdate(event) {
    console.log("Manual financial update requested")
    this.updateStatus('processing')
    
    // The actual API call is handled by the button component
    // We just update the UI state here
  }
  
  // Refresh the financial data component
  async refreshFinancialData() {
    try {
      const response = await fetch(`/companies/${this.companyIdValue}/financial_data`, {
        headers: {
          'Accept': 'text/vnd.turbo-stream.html',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })
      
      if (response.ok) {
        const html = await response.text()
        Turbo.renderStreamMessage(html)
      }
    } catch (error) {
      console.error('Error refreshing financial data:', error)
    }
  }
  
  // Update the last updated timestamp
  updateTimestamp(timestamp) {
    if (this.hasLastUpdatedTarget) {
      const date = new Date(timestamp)
      this.lastUpdatedTarget.textContent = this.formatTimestamp(date)
    }
  }
  
  // Update the status indicator
  updateStatus(status) {
    if (this.hasStatusTarget) {
      this.statusTarget.className = this.getStatusClasses(status)
      this.statusTarget.textContent = this.getStatusText(status)
    }
  }
  
  // Fallback polling for when WebSocket connection is lost
  startFallbackPolling() {
    if (this.fallbackTimer) return // Already polling
    
    console.log("Starting fallback polling for financial data")
    this.fallbackTimer = setInterval(() => {
      this.refreshFinancialData()
    }, this.fallbackIntervalValue)
  }
  
  stopFallbackPolling() {
    if (this.fallbackTimer) {
      clearInterval(this.fallbackTimer)
      this.fallbackTimer = null
      console.log("Stopped fallback polling")
    }
  }
  
  // Helper methods
  formatTimestamp(date) {
    return date.toLocaleString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    })
  }
  
  getStatusClasses(status) {
    const baseClasses = "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium"
    switch (status) {
      case 'success':
        return `${baseClasses} bg-green-100 text-green-800 dark:bg-green-900/20 dark:text-green-400`
      case 'processing':
        return `${baseClasses} bg-yellow-100 text-yellow-800 dark:bg-yellow-900/20 dark:text-yellow-400`
      case 'failed':
        return `${baseClasses} bg-red-100 text-red-800 dark:bg-red-900/20 dark:text-red-400`
      default:
        return `${baseClasses} bg-gray-100 text-gray-800 dark:bg-gray-900/20 dark:text-gray-400`
    }
  }
  
  getStatusText(status) {
    switch (status) {
      case 'success': return 'Updated'
      case 'processing': return 'Processing...'
      case 'failed': return 'Failed'
      default: return 'Unknown'
    }
  }
}
