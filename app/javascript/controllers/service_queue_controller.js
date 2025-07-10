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
    console.log("Service name:", this.serviceNameValue)
    event.preventDefault()
    event.stopPropagation()
    
    const form = this.formTarget
    const submitButton = this.submitButtonTarget
    const countInput = this.countInputTarget
    
    console.log("Form action URL:", form.action)
    console.log("Form method:", form.method)
    
    // Make sure we get the current value from the input field
    const count = parseInt(countInput.value) || 0
    const maxAvailable = parseInt(countInput.dataset.maxAvailable || 1000)
    
    console.log("Form action:", form.action)
    console.log("Count input element:", countInput)
    console.log("Count value from input:", countInput.value)
    console.log("Parsed count:", count)
    console.log("Max available:", maxAvailable)
    
    // Client-side validation
    if (count <= 0) {
      this.showError('Count must be greater than 0')
      return
    }
    
    if (count > maxAvailable) {
      const entityType = window.location.pathname.includes('/companies') ? 'companies' : 'domains';
      this.showError(`Only ${maxAvailable} ${entityType} are available for testing`)
      return
    }
    
    if (count > 1000) {
      const entityType = window.location.pathname.includes('/companies') ? 'companies' : 'domains';
      this.showError(`Cannot queue more than 1000 ${entityType} at once`)
      return
    }
    
    // Disable form during submission IMMEDIATELY
    this.setLoading(true)
    
    try {
      const formData = new FormData(form)
      
      // Ensure count value is explicitly set in FormData
      formData.set('count', count.toString())
      
      const response = await fetch(form.action, {
        method: 'POST',
        body: formData,
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        },
        credentials: 'same-origin'
      })
      
      const data = await response.json()
      
      if (data.success) {
        this.showSuccess(data.message, data.queued_count)
        
        // Trigger immediate service stats update for real-time feel
        const serviceStatsEvent = new CustomEvent('service-stats:update')
        document.dispatchEvent(serviceStatsEvent)
        
        // Update available count if provided
        if (data.available_count !== undefined) {
          this.updateAvailableCount(data.available_count)
        }
        // Update max attributes but don't change the user's input value
        if (data.available_count !== undefined) {
          countInput.max = Math.min(data.available_count, 1000)
          countInput.dataset.maxAvailable = data.available_count
        }
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
      submitButton.innerHTML = 'Queue Processing'
    }
  }
  
  showSuccess(message, count) {
    const entityType = window.location.pathname.includes('/companies') ? 'companies' : 'domains';
    this.showToast(message + ` (${count} ${entityType} queued)`, 'success')
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
      // Determine the correct endpoint based on current page
      const currentPath = window.location.pathname;
      let statusEndpoint;
      
      if (currentPath.includes('/companies')) {
        statusEndpoint = '/companies/enhancement_queue_status';
      } else if (currentPath.includes('/domains')) {
        statusEndpoint = '/domains/queue_status';
      } else {
        // Default fallback
        statusEndpoint = '/domains/queue_status';
      }
      
      const response = await fetch(window.location.origin + statusEndpoint)
      const data = await response.json()
      
      if (data.success) {
        // Update queue stats directly
        this.updateQueueElements(data.queue_stats)
        console.log('Queue stats updated successfully')
      }
      
      // Trigger immediate service stats update for real-time feel
      const serviceStatsEvent = new CustomEvent('service-stats:update')
      document.dispatchEvent(serviceStatsEvent)
      
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
    // Update all queue stat elements by finding all elements with data-queue-stat attribute
    document.querySelectorAll('[data-queue-stat]').forEach(element => {
      const queueName = element.getAttribute('data-queue-stat');
      if (queueStats[queueName] !== undefined) {
        const formattedValue = (queueStats[queueName] || 0).toLocaleString();
        // If it's in a button, add " in queue" text
        if (element.classList.contains('queue-button-stat') || element.textContent.includes('in queue')) {
          element.textContent = formattedValue + ' in queue';
        } else {
          element.textContent = formattedValue;
        }
      }
    });
    
    // Update total processed stat
    const processed = document.querySelector('[data-stat="processed"]');
    if (processed) processed.textContent = (queueStats.total_processed || 0).toLocaleString();
    
    // Update generic stat elements
    document.querySelectorAll('[data-stat]').forEach(element => {
      const statName = element.getAttribute('data-stat');
      if (queueStats[statName] !== undefined) {
        element.textContent = (queueStats[statName] || 0).toLocaleString();
      }
    });
  }
  
  updateAvailableCount(availableCount) {
    // Update the available count display for this service
    const availableElement = document.querySelector(`[data-available-count="${this.serviceNameValue}"]`);
    if (availableElement) {
      const entityType = window.location.pathname.includes('/companies') ? 'companies need processing' : 'domains need testing';
      const formattedCount = availableCount.toLocaleString();
      availableElement.textContent = `${formattedCount} ${entityType}`;
    }
    
    // Update the input max attribute and data attribute
    const countInput = this.countInputTarget;
    if (countInput) {
      countInput.dataset.maxAvailable = availableCount;
      countInput.max = Math.min(availableCount, 1000);
      
      // Only reduce value if it exceeds available AND input is not currently focused
      if (parseInt(countInput.value) > availableCount && document.activeElement !== countInput) {
        countInput.value = Math.min(availableCount, parseInt(countInput.value));
      }
    }
  }
}