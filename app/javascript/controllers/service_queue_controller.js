import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "submitButton", "countInput", "statusText"]
  static values = { serviceName: String }

  connect() {
    console.log("Service queue controller connected for:", this.serviceNameValue)
    console.log("Form target:", this.formTarget)
    console.log("Submit button target:", this.submitButtonTarget)
  }

  async submit(event) {
    console.log("Submit event triggered!", event)
    event.preventDefault()
    event.stopPropagation()
    
    const form = this.formTarget
    const submitButton = this.submitButtonTarget
    const countInput = this.countInputTarget
    const count = parseInt(countInput.value)
    const maxAvailable = parseInt(countInput.dataset.maxAvailable || 1000)
    
    console.log("Form action:", form.action)
    console.log("Count value:", count)
    console.log("Max available:", maxAvailable)
    
    // Client-side validation
    if (count <= 0) {
      this.showError('Count must be greater than 0')
      return
    }
    
    if (count > maxAvailable) {
      this.showError(`Only ${maxAvailable} domains are available for testing`)
      return
    }
    
    if (count > 1000) {
      this.showError('Cannot queue more than 1000 domains at once')
      return
    }
    
    // Disable form during submission IMMEDIATELY
    this.setLoading(true)
    
    try {
      const formData = new FormData(form)
      
      const response = await fetch(form.action, {
        method: 'POST',
        body: formData,
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })
      
      const data = await response.json()
      
      if (data.success) {
        this.showSuccess(data.message, data.queued_count)
        // Update available count if provided
        if (data.available_count !== undefined) {
          this.updateAvailableCount(data.available_count)
        }
        // Reset form to sensible default
        const newMax = Math.min(data.available_count || maxAvailable, 10)
        countInput.value = newMax
        // Trigger a queue status update and wait for it to complete
        await this.updateQueueStats()
        // Only re-enable the button after queue stats are updated
        this.setLoading(false)
      } else {
        this.showError(data.message || 'Failed to queue domains')
        this.setLoading(false)
      }
    } catch (error) {
      console.error('Error submitting form:', error)
      this.showError('Network error occurred')
      this.setLoading(false)
    }
  }
  
  setLoading(loading) {
    const submitButton = this.submitButtonTarget
    const countInput = this.countInputTarget
    
    if (loading) {
      // Disable button and input
      submitButton.disabled = true
      countInput.disabled = true
      
      // Add visual loading state
      submitButton.style.opacity = '0.6'
      submitButton.style.cursor = 'not-allowed'
      
      // Update button text with spinner
      submitButton.innerHTML = `
        <svg class="animate-spin -ml-1 mr-3 h-5 w-5 text-white inline" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
        </svg>
        Processing...
      `
    } else {
      // Re-enable button and input
      submitButton.disabled = false
      countInput.disabled = false
      
      // Reset visual state
      submitButton.style.opacity = '1'
      submitButton.style.cursor = 'pointer'
      
      // Reset button text
      submitButton.innerHTML = 'Queue Testing'
    }
  }
  
  showSuccess(message, count) {
    this.showToast(message + ` (${count} domains queued)`, 'success')
  }
  
  showError(message) {
    this.showToast(message, 'error')
  }
  
  showToast(message, type) {
    // Create toast notification
    const toast = document.createElement('div')
    toast.className = `fixed top-4 right-4 p-4 rounded-lg shadow-lg z-50 text-white max-w-sm ${
      type === 'success' ? 'bg-green-500' : 'bg-red-500'
    }`
    toast.innerHTML = `
      <div class="flex items-center">
        <div class="flex-shrink-0">
          ${type === 'success' ? 
            '<svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"></path></svg>' :
            '<svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"></path></svg>'
          }
        </div>
        <div class="ml-3 flex-1">
          <p class="text-sm font-medium">${message}</p>
        </div>
        <div class="ml-4 flex-shrink-0">
          <button class="inline-flex text-white hover:text-gray-200 focus:outline-none" onclick="this.parentElement.parentElement.parentElement.remove()">
            <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd"></path>
            </svg>
          </button>
        </div>
      </div>
    `
    
    document.body.appendChild(toast)
    
    // Auto-remove after 5 seconds
    setTimeout(() => {
      if (toast.parentNode) {
        toast.parentNode.removeChild(toast)
      }
    }, 5000)
  }
  
  async updateQueueStats() {
    // Make the queue status request directly and wait for it to complete
    try {
      const response = await fetch(window.location.origin + '/domains/queue_status')
      const data = await response.json()
      
      if (data.success) {
        // Update queue stats directly
        this.updateQueueElements(data.queue_stats)
        console.log('Queue stats updated successfully')
      }
      
      // Also trigger the global event for other listeners
      const event = new CustomEvent('updateQueueStats')
      window.dispatchEvent(event)
    } catch (error) {
      console.error('Error updating queue stats:', error)
      // Still trigger the global event as fallback
      const event = new CustomEvent('updateQueueStats')
      window.dispatchEvent(event)
    }
  }
  
  updateQueueElements(queueStats) {
    // Update queue stats if elements exist
    const dnsQueue = document.querySelector('[data-stat="domain_dns_testing"]');
    const mxQueue = document.querySelector('[data-stat="domain_mx_testing"]');
    const aRecordQueue = document.querySelector('[data-stat="DomainARecordTestingService"]');
    const processed = document.querySelector('[data-stat="processed"]');
    
    if (dnsQueue) dnsQueue.textContent = queueStats.domain_dns_testing || 0;
    if (mxQueue) mxQueue.textContent = queueStats.domain_mx_testing || 0;
    if (aRecordQueue) aRecordQueue.textContent = queueStats.DomainARecordTestingService || 0;
    if (processed) processed.textContent = queueStats.total_processed || 0;
    
    // Also update queue counts in the service buttons
    const dnsQueueInButton = document.querySelector('[data-queue-stat="domain_dns_testing"]');
    const mxQueueInButton = document.querySelector('[data-queue-stat="domain_mx_testing"]');
    const aRecordQueueInButton = document.querySelector('[data-queue-stat="DomainARecordTestingService"]');
    
    if (dnsQueueInButton) dnsQueueInButton.textContent = (queueStats.domain_dns_testing || 0) + ' in queue';
    if (mxQueueInButton) mxQueueInButton.textContent = (queueStats.domain_mx_testing || 0) + ' in queue';
    if (aRecordQueueInButton) aRecordQueueInButton.textContent = (queueStats.DomainARecordTestingService || 0) + ' in queue';
  }
  
  updateAvailableCount(availableCount) {
    // Update the available count display for this service
    const availableElement = document.querySelector(`[data-available-count="${this.serviceNameValue}"]`);
    if (availableElement) {
      availableElement.textContent = `${availableCount} domains need testing`;
    }
    
    // Update the input max attribute and data attribute
    const countInput = this.countInputTarget;
    if (countInput) {
      countInput.dataset.maxAvailable = availableCount;
      countInput.max = Math.min(availableCount, 1000);
      
      // If current value exceeds available, reduce it
      if (parseInt(countInput.value) > availableCount) {
        countInput.value = Math.min(availableCount, 10);
      }
    }
  }
}