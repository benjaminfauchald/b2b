import { Controller } from "@hotwired/stimulus"

// LinkedIn Company Data Controller
// Handles UI interactions for LinkedIn company data extraction
export default class extends Controller {
  static targets = ["button", "status", "result"]
  static values = { 
    companyId: Number,
    pollingInterval: { type: Number, default: 2000 },
    maxPollingTime: { type: Number, default: 30000 }
  }

  connect() {
    console.log("LinkedIn Company Data controller connected")
    this.pollingTimer = null
    this.maxPollingTimer = null
  }

  disconnect() {
    this.stopPolling()
  }

  extractData(event) {
    console.log("Starting LinkedIn company data extraction")
    
    // Update button state
    this.setButtonState('processing')
    
    // Start polling for status updates
    this.startPolling()
  }

  startPolling() {
    console.log("Starting status polling")
    
    this.pollingTimer = setInterval(() => {
      this.checkStatus()
    }, this.pollingIntervalValue)
    
    // Set maximum polling time
    this.maxPollingTimer = setTimeout(() => {
      console.log("Polling timeout reached")
      this.stopPolling()
      this.setButtonState('timeout')
    }, this.maxPollingTimeValue)
  }

  stopPolling() {
    if (this.pollingTimer) {
      clearInterval(this.pollingTimer)
      this.pollingTimer = null
    }
    
    if (this.maxPollingTimer) {
      clearTimeout(this.maxPollingTimer)
      this.maxPollingTimer = null
    }
  }

  async checkStatus() {
    try {
      const response = await fetch(`/companies/${this.companyIdValue}/linkedin_company_data_status`, {
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })
      
      if (response.ok) {
        const data = await response.json()
        this.updateStatus(data)
        
        // Stop polling if extraction is complete
        if (data.status === 'success' || data.status === 'failed') {
          this.stopPolling()
        }
      }
    } catch (error) {
      console.error('Error checking LinkedIn extraction status:', error)
      this.stopPolling()
      this.setButtonState('error')
    }
  }

  updateStatus(data) {
    console.log("Status update:", data)
    
    this.setButtonState(data.status)
    
    if (data.status === 'success') {
      this.showSuccessMessage(data.company_data)
    } else if (data.status === 'failed') {
      this.showErrorMessage(data.error)
    }
  }

  setButtonState(status) {
    const button = this.buttonTarget
    const statusElement = this.hasStatusTarget ? this.statusTarget : null
    
    // Reset button classes
    button.classList.remove('btn-primary', 'btn-success', 'btn-danger', 'btn-warning')
    
    switch (status) {
      case 'processing':
        button.classList.add('btn-warning')
        button.disabled = true
        button.innerHTML = '<i class="fas fa-spinner fa-spin"></i> <span>Processing...</span>'
        if (statusElement) statusElement.textContent = 'Processing'
        break
        
      case 'success':
        button.classList.add('btn-success')
        button.disabled = false
        button.innerHTML = '<i class="fas fa-check-circle"></i> <span>Extract LinkedIn Data</span>'
        if (statusElement) statusElement.textContent = 'Success'
        break
        
      case 'failed':
      case 'error':
        button.classList.add('btn-danger')
        button.disabled = false
        button.innerHTML = '<i class="fas fa-exclamation-triangle"></i> <span>Extract LinkedIn Data</span>'
        if (statusElement) statusElement.textContent = 'Failed'
        break
        
      case 'timeout':
        button.classList.add('btn-warning')
        button.disabled = false
        button.innerHTML = '<i class="fas fa-clock"></i> <span>Extract LinkedIn Data</span>'
        if (statusElement) statusElement.textContent = 'Timeout'
        break
        
      default:
        button.classList.add('btn-primary')
        button.disabled = false
        button.innerHTML = '<i class="fab fa-linkedin"></i> <span>Extract LinkedIn Data</span>'
        if (statusElement) statusElement.textContent = ''
    }
  }

  showSuccessMessage(companyData) {
    if (this.hasResultTarget) {
      this.resultTarget.innerHTML = `
        <div class="alert alert-success mt-2">
          <h6><i class="fas fa-check-circle"></i> LinkedIn Data Extracted Successfully</h6>
          <p class="mb-1"><strong>Company:</strong> ${companyData.name}</p>
          <p class="mb-1"><strong>LinkedIn ID:</strong> ${companyData.id}</p>
          <p class="mb-1"><strong>Industry:</strong> ${companyData.industry || 'N/A'}</p>
          <p class="mb-1"><strong>Staff Count:</strong> ${companyData.staff_count || 'N/A'}</p>
          <p class="mb-0"><strong>Website:</strong> ${companyData.website || 'N/A'}</p>
        </div>
      `
    }
    
    // Show toast notification
    this.showToast('LinkedIn company data extracted successfully!', 'success')
  }

  showErrorMessage(error) {
    if (this.hasResultTarget) {
      this.resultTarget.innerHTML = `
        <div class="alert alert-danger mt-2">
          <h6><i class="fas fa-exclamation-triangle"></i> LinkedIn Data Extraction Failed</h6>
          <p class="mb-0">${error}</p>
        </div>
      `
    }
    
    // Show toast notification
    this.showToast(`LinkedIn extraction failed: ${error}`, 'error')
  }

  showToast(message, type = 'info') {
    // Create toast notification
    const toast = document.createElement('div')
    toast.className = `toast align-items-center text-white bg-${type === 'success' ? 'success' : 'danger'} border-0`
    toast.setAttribute('role', 'alert')
    toast.setAttribute('aria-live', 'assertive')
    toast.setAttribute('aria-atomic', 'true')
    
    toast.innerHTML = `
      <div class="d-flex">
        <div class="toast-body">
          ${message}
        </div>
        <button type="button" class="btn-close btn-close-white me-2 m-auto" data-bs-dismiss="toast"></button>
      </div>
    `
    
    // Add to toast container
    let toastContainer = document.querySelector('.toast-container')
    if (!toastContainer) {
      toastContainer = document.createElement('div')
      toastContainer.className = 'toast-container position-fixed top-0 end-0 p-3'
      document.body.appendChild(toastContainer)
    }
    
    toastContainer.appendChild(toast)
    
    // Show toast
    const bsToast = new bootstrap.Toast(toast, { delay: 5000 })
    bsToast.show()
    
    // Remove toast element after it's hidden
    toast.addEventListener('hidden.bs.toast', () => {
      toast.remove()
    })
  }
}