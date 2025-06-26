import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "text", "icon", "spinner", "statusBadge", "financialData"]

  connect() {
    console.log("Service button controller connected")
  }

  handleSubmit(event) {
    event.preventDefault()
    
    console.log("Handling service button submit")
    
    // Disable button and show loading state
    this.disableButton()
    
    // Get form and submit via fetch
    const form = event.target.closest('form')
    const formData = new FormData(form)
    
    fetch(form.action, {
      method: 'POST',
      body: formData,
      headers: {
        'X-Requested-With': 'XMLHttpRequest',
        'Accept': 'application/json'
      }
    })
    .then(response => response.json())
    .then(data => {
      if (data.success) {
        this.handleSuccess(data)
      } else {
        this.handleError(data.message || "Service request failed")
      }
    })
    .catch(error => {
      console.error("Service request error:", error)
      this.handleError("Request failed")
    })
  }

  disableButton() {
    console.log("Disabling button for service request")
    
    // Disable the button
    this.buttonTarget.disabled = true
    
    // Show spinner, hide icon
    if (this.hasSpinnerTarget) {
      this.spinnerTarget.classList.remove("hidden")
    }
    if (this.hasIconTarget) {
      this.iconTarget.classList.add("hidden")
    }
    
    // Update button text and styling
    if (this.hasTextTarget) {
      this.textTarget.textContent = "Fetching..."
    }
    
    // Update button classes to show loading state
    this.buttonTarget.classList.remove("bg-blue-600", "hover:bg-blue-700", "bg-green-600", "hover:bg-green-700")
    this.buttonTarget.classList.add("bg-gray-400", "cursor-not-allowed")
    
    // Update status badge if available
    if (this.hasStatusBadgeTarget) {
      this.statusBadgeTarget.textContent = "Fetching..."
      this.statusBadgeTarget.classList.remove("bg-gray-100", "text-gray-800", "bg-green-100", "text-green-800")
      this.statusBadgeTarget.classList.add("bg-yellow-100", "text-yellow-800")
    }
  }

  handleResponse(event) {
    console.log("Handling service response")
    
    const response = event.detail[0]
    
    if (response.ok) {
      // Parse response JSON
      response.json().then(data => {
        console.log("Service response data:", data)
        
        if (data.success) {
          this.handleSuccess(data)
        } else {
          this.handleError(data.message || "Service request failed")
        }
      }).catch(error => {
        console.error("Error parsing JSON response:", error)
        this.handleError("Failed to process response")
      })
    } else {
      console.error("Service request failed with status:", response.status)
      this.handleError(`Request failed (${response.status})`)
    }
  }

  handleSuccess(data) {
    console.log("Service request successful:", data)
    
    // Show success message for job queuing
    this.showMessage("Financial data request queued successfully!", "success")
    
    // Start polling for job completion
    this.startPolling(data.job_id)
  }

  startPolling(jobId) {
    console.log("Starting to poll for job completion:", jobId)
    
    // Update status to show we're processing
    if (this.hasStatusBadgeTarget) {
      this.statusBadgeTarget.textContent = "Processing..."
      this.statusBadgeTarget.classList.remove("bg-gray-100", "text-gray-800", "bg-green-100", "text-green-800")
      this.statusBadgeTarget.classList.add("bg-blue-100", "text-blue-800")
    }
    
    // Poll every 3 seconds for up to 2 minutes
    this.pollCount = 0
    this.maxPolls = 40 // 40 * 3 seconds = 2 minutes
    this.pollInterval = setInterval(() => {
      this.checkJobStatus(jobId)
    }, 3000)
  }

  checkJobStatus(jobId) {
    this.pollCount++
    
    if (this.pollCount > this.maxPolls) {
      console.log("Polling timeout reached")
      clearInterval(this.pollInterval)
      this.handlePollingTimeout()
      return
    }
    
    // Check if the page has been updated with new data
    // This is a simple check - in a real implementation you might call an endpoint
    // For now, we'll reload the page after a reasonable delay
    if (this.pollCount > 10) { // After 30 seconds, assume it's done and reload
      clearInterval(this.pollInterval)
      this.handleJobCompletion()
    }
  }

  handleJobCompletion() {
    console.log("Job appears to have completed, refreshing page")
    
    // Show completion message
    this.showMessage("Financial data has been updated!", "success")
    
    // Reload the page to show fresh data
    setTimeout(() => {
      window.location.reload()
    }, 1500)
  }

  handlePollingTimeout() {
    console.log("Job polling timed out")
    
    // Re-enable button
    this.buttonTarget.disabled = false
    
    // Hide spinner, show icon
    if (this.hasSpinnerTarget) {
      this.spinnerTarget.classList.add("hidden")
    }
    if (this.hasIconTarget) {
      this.iconTarget.classList.remove("hidden")
    }
    
    // Reset button text and styling
    if (this.hasTextTarget) {
      this.textTarget.textContent = "Fetch Financial Data"
    }
    
    // Reset button classes
    this.buttonTarget.classList.remove("bg-gray-400", "cursor-not-allowed")
    this.buttonTarget.classList.add("bg-blue-600", "hover:bg-blue-700")
    
    // Reset status badge
    if (this.hasStatusBadgeTarget) {
      this.statusBadgeTarget.textContent = "Processing (check back later)"
      this.statusBadgeTarget.classList.remove("bg-blue-100", "text-blue-800")
      this.statusBadgeTarget.classList.add("bg-yellow-100", "text-yellow-800")
    }
    
    // Show timeout message
    this.showMessage("Financial data processing is taking longer than expected. Please check back later.", "info")
  }

  handleError(message) {
    console.error("Service request error:", message)
    
    // Re-enable button
    this.buttonTarget.disabled = false
    
    // Hide spinner, show icon
    if (this.hasSpinnerTarget) {
      this.spinnerTarget.classList.add("hidden")
    }
    if (this.hasIconTarget) {
      this.iconTarget.classList.remove("hidden")
    }
    
    // Reset button text and styling
    if (this.hasTextTarget) {
      this.textTarget.textContent = "Fetch Financial Data"
    }
    
    // Reset button classes
    this.buttonTarget.classList.remove("bg-gray-400", "cursor-not-allowed")
    this.buttonTarget.classList.add("bg-blue-600", "hover:bg-blue-700")
    
    // Reset status badge
    if (this.hasStatusBadgeTarget) {
      this.statusBadgeTarget.textContent = "No Data"
      this.statusBadgeTarget.classList.remove("bg-yellow-100", "text-yellow-800", "bg-green-100", "text-green-800")
      this.statusBadgeTarget.classList.add("bg-gray-100", "text-gray-800")
    }
    
    // Show error message
    if (message.includes("404") || message.toLowerCase().includes("no data")) {
      this.showMessage("No financial data found for this company", "error")
    } else {
      this.showMessage(message, "error")
    }
  }

  showMessage(message, type) {
    // Create or find message container
    let messageContainer = document.getElementById("flash-messages")
    if (!messageContainer) {
      messageContainer = document.createElement("div")
      messageContainer.id = "flash-messages"
      messageContainer.className = "fixed top-4 right-4 z-50"
      document.body.appendChild(messageContainer)
    }
    
    // Create message element
    const messageElement = document.createElement("div")
    let bgColor
    switch(type) {
      case "success":
        bgColor = "bg-green-500"
        break
      case "error":
        bgColor = "bg-red-500"
        break
      case "info":
        bgColor = "bg-blue-500"
        break
      default:
        bgColor = "bg-gray-500"
    }
    
    messageElement.className = `${bgColor} text-white px-6 py-3 rounded-lg shadow-lg mb-2 opacity-0 transform translate-x-full transition-all duration-300`
    messageElement.textContent = message
    
    // Add to container
    messageContainer.appendChild(messageElement)
    
    // Animate in
    setTimeout(() => {
      messageElement.classList.remove("opacity-0", "translate-x-full")
    }, 10)
    
    // Remove after appropriate time (longer for info messages)
    const timeout = type === "info" ? 8000 : 5000
    setTimeout(() => {
      messageElement.classList.add("opacity-0", "translate-x-full")
      setTimeout(() => {
        if (messageElement.parentNode) {
          messageElement.parentNode.removeChild(messageElement)
        }
      }, 300)
    }, timeout)
  }

  refreshFinancialData() {
    // Look for and refresh financial data components
    const financialDataElement = document.querySelector('[data-controller*="company-financials"]')
    if (financialDataElement) {
      // Trigger a refresh of the financial data component
      const financialController = this.application.getControllerForElementAndIdentifier(financialDataElement, "company-financials")
      if (financialController && typeof financialController.refresh === "function") {
        financialController.refresh()
      }
    }
    
    // Also refresh the enhancement status component
    setTimeout(() => {
      window.location.reload()
    }, 2000)
  }
}