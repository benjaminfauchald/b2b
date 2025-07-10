import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="postal-code-form"
export default class extends Controller {
  static targets = ["postalCodeInput", "preview", "previewText", "errorMessage"]
  static values = { updateUrl: String }

  connect() {
    console.log('PostalCodeFormController connected')
    this.updatePreview()
    
    // Get the submit button and add click handler
    const submitButton = document.getElementById('postal-code-submit-button')
    if (submitButton) {
      console.log('Found submit button:', submitButton)
      submitButton.addEventListener('click', (e) => {
        console.log('Submit button clicked!', e)
        console.log('Form valid:', this.element.checkValidity())
        console.log('Button disabled:', submitButton.disabled)
      })
    } else {
      console.error('Submit button not found!')
    }
    
    // Listen for form submission events
    this.element.addEventListener('submit', (e) => {
      console.log('Form submit event triggered', e)
    })
    
    this.element.addEventListener('turbo:submit-start', (e) => {
      console.log('Turbo submit start', e)
    })
    
    this.element.addEventListener('turbo:submit-end', this.handleFormSubmission.bind(this))
    
    // Add more Turbo event listeners for debugging
    this.element.addEventListener('turbo:before-fetch-request', (e) => {
      console.log('Turbo before fetch request:', e.detail)
      try {
        console.log('Request URL:', e.detail.url.toString())
        console.log('Request method:', e.detail.fetchOptions.method)
        console.log('Request body:', e.detail.fetchOptions.body)
        
        // Log form data
        if (e.detail.fetchOptions.body instanceof FormData) {
          console.log('Form data entries:')
          for (let [key, value] of e.detail.fetchOptions.body.entries()) {
            console.log(`  ${key}: ${value}`)
          }
        } else if (e.detail.fetchOptions.body instanceof URLSearchParams) {
          console.log('URL params entries:')
          for (let [key, value] of e.detail.fetchOptions.body.entries()) {
            console.log(`  ${key}: ${value}`)
          }
        }
      } catch (error) {
        console.error('Error logging request details:', error)
      }
    })
    
    this.element.addEventListener('turbo:before-fetch-response', async (e) => {
      console.log('Turbo before fetch response:', e.detail)
      console.log('Response status:', e.detail.fetchResponse.response.status)
      console.log('Response URL:', e.detail.fetchResponse.response.url)
      console.log('Response headers:', e.detail.fetchResponse.response.headers)
      
      // Try to read the response body
      try {
        const responseText = await e.detail.fetchResponse.response.clone().text()
        console.log('Response body preview:', responseText.substring(0, 500))
        
        // Check if toast is in the response
        if (responseText.includes('toast-success') || responseText.includes('toast-warning')) {
          console.log('Toast notification found in response!')
          
          // Look for the full toast content
          const toastMatch = responseText.match(/<turbo-stream action="append"[^>]*>[\s\S]*?<\/turbo-stream>/g)
          if (toastMatch) {
            console.log('Toast turbo-stream:', toastMatch[toastMatch.length - 1])
          }
        }
      } catch (error) {
        console.error('Error reading response body:', error)
      }
    })
    
    this.element.addEventListener('turbo:fetch-request-error', (e) => {
      console.error('Turbo fetch request error:', e.detail)
    })
  }

  handleFormSubmission(event) {
    console.log('Form submission ended:', event)
    console.log('Submission success:', event.detail.success)
    console.log('Submission detail:', event.detail)
    
    // Check if the form submission was successful
    if (event.detail.success) {
      // Dispatch event to trigger immediate service stats update
      const serviceStatsEvent = new CustomEvent('service-stats:update')
      document.dispatchEvent(serviceStatsEvent)
      
      // Check for toast notifications after a short delay
      setTimeout(() => {
        const toasts = document.querySelectorAll('[id^="toast-"]')
        console.log('Toast elements found on page:', toasts.length)
        toasts.forEach(toast => {
          console.log('Toast element:', toast)
          console.log('Toast position:', {
            top: toast.style.top,
            right: toast.style.right,
            zIndex: window.getComputedStyle(toast).zIndex,
            display: window.getComputedStyle(toast).display,
            visibility: window.getComputedStyle(toast).visibility,
            opacity: window.getComputedStyle(toast).opacity
          })
        })
      }, 100)
    }
  }

  validateAndUpdatePreview(event) {
    const input = event.target
    const value = input.value
    
    // Only allow digits
    const cleanValue = value.replace(/[^\d]/g, '')
    if (cleanValue !== value) {
      input.value = cleanValue
    }
    
    // Validate length
    if (cleanValue.length === 4) {
      this.hideError()
      this.updatePreview()
    } else {
      if (cleanValue.length > 0) {
        this.showError()
      } else {
        this.hideError()
      }
      this.previewTextTarget.textContent = "Enter a 4-digit postal code to see preview"
      this.hideQuotaWarning()
    }
  }
  
  showError() {
    if (this.hasErrorMessageTarget) {
      this.errorMessageTarget.classList.remove('hidden')
    }
  }
  
  hideError() {
    if (this.hasErrorMessageTarget) {
      this.errorMessageTarget.classList.add('hidden')
    }
  }

  updatePreview() {
    const postalCode = this.getPostalCode()
    const batchSize = this.getBatchSize()
    
    if (postalCode && postalCode.length === 4) {
      this.fetchPreviewData(postalCode, batchSize)
      this.checkQuotaStatus(batchSize)
    } else {
      this.previewTextTarget.textContent = "Enter a 4-digit postal code to see preview"
      this.hideQuotaWarning()
    }
  }

  async fetchPreviewData(postalCode, batchSize) {
    try {
      const response = await fetch(`/companies/postal_code_preview?postal_code=${postalCode}&batch_size=${batchSize}`, {
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })

      if (response.ok) {
        const data = await response.json()
        this.updatePreviewText(data)
      } else {
        this.previewTextTarget.textContent = "Error loading preview data"
      }
    } catch (error) {
      console.error('Error fetching preview data:', error)
      this.previewTextTarget.textContent = "Error loading preview data"
    }
  }

  updatePreviewText(data) {
    if (data.count === 0) {
      this.previewTextTarget.textContent = `No companies found in postal code ${data.postal_code}`
      this.updateButtonState(false, "No Companies Found")
      this.updateBatchSizeOptions([]) // Empty array when no companies
      return
    }

    // Update batch size options based on available companies
    this.updateBatchSizeOptions(data.batch_size_options || [])

    const batchText = data.batch_size < data.count ? `top ${data.batch_size}` : `all ${data.count}`
    
    if (data.revenue_range) {
      const text = `${data.count} companies found. Will process ${batchText} (revenue range: ${data.revenue_range.lowest} - ${data.revenue_range.highest})`
      this.previewTextTarget.textContent = text
    } else {
      this.previewTextTarget.textContent = `${data.count} companies found. Will process ${batchText}`
    }
    
    // Update button state based on validation
    const canProcess = data.count > 0 && data.batch_size <= data.count
    if (canProcess) {
      this.updateButtonState(true, "Queue LinkedIn Discovery")
    } else {
      this.updateButtonState(false, "Batch Size Too Large")
    }
  }
  
  updateBatchSizeOptions(options) {
    const batchSizeSelect = this.element.querySelector('select[name="batch_size"]')
    if (!batchSizeSelect) return
    
    const currentValue = batchSizeSelect.value
    
    // Clear existing options
    batchSizeSelect.innerHTML = ''
    
    if (options.length === 0) {
      // No companies available - show disabled message
      const option = document.createElement('option')
      option.value = ''
      option.textContent = 'No companies available'
      option.disabled = true
      option.selected = true
      batchSizeSelect.appendChild(option)
      batchSizeSelect.disabled = true
    } else {
      // Add new options
      batchSizeSelect.disabled = false
      options.forEach(value => {
        const option = document.createElement('option')
        option.value = value
        option.textContent = value
        if (value.toString() === currentValue) {
          option.selected = true
        }
        batchSizeSelect.appendChild(option)
      })
      
      // If current value is not in new options, select the first one
      if (!options.includes(parseInt(currentValue))) {
        batchSizeSelect.value = options[0]
      }
    }
  }

  updateButtonState(enabled, buttonText) {
    const submitButton = document.getElementById('postal-code-submit-button')
    if (submitButton) {
      submitButton.disabled = !enabled
      submitButton.value = buttonText
      
      // Update button styling
      if (enabled) {
        submitButton.className = "text-white bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:ring-blue-300 font-medium rounded-lg text-sm px-5 py-2.5 text-center dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
      } else {
        submitButton.className = "text-white bg-gray-400 cursor-not-allowed font-medium rounded-lg text-sm px-5 py-2.5 text-center"
      }
    }
  }

  getPostalCode() {
    const postalCodeInput = this.element.querySelector('input[name="postal_code"]')
    return postalCodeInput ? postalCodeInput.value : null
  }

  getBatchSize() {
    const batchSizeSelect = this.element.querySelector('select[name="batch_size"]')
    return batchSizeSelect ? parseInt(batchSizeSelect.value) : 100
  }

  async checkQuotaStatus(requestedJobs) {
    try {
      const response = await fetch(`/companies/check_google_api_quota?batch_size=${requestedJobs}`, {
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })

      if (response.ok) {
        const data = await response.json()
        this.updateQuotaDisplay(data)
      } else {
        console.error('Error checking quota status')
        this.hideQuotaWarning()
      }
    } catch (error) {
      console.error('Error checking quota status:', error)
      this.hideQuotaWarning()
    }
  }

  updateQuotaDisplay(quotaData) {
    const quotaStatus = document.getElementById('quota-status')
    const quotaMessage = document.getElementById('quota-message')
    const quotaInfo = document.getElementById('quota-info')
    const submitButton = document.getElementById('postal-code-submit-button')

    if (quotaData.quota_exceeded) {
      // Show warning and disable button
      quotaStatus.classList.remove('hidden')
      quotaMessage.textContent = quotaData.message
      
      if (submitButton) {
        submitButton.disabled = true
        submitButton.value = "Quota Exceeded"
        submitButton.className = "text-white bg-gray-400 cursor-not-allowed font-medium rounded-lg text-sm px-5 py-2.5 text-center"
      }
    } else {
      // Hide warning but show quota info
      quotaStatus.classList.add('hidden')
      
      if (quotaInfo) {
        quotaInfo.textContent = `Estimated API usage: ${quotaData.estimated_calls} calls (${quotaData.used_today}/${quotaData.daily_limit} used today)`
      }
    }
  }

  hideQuotaWarning() {
    const quotaStatus = document.getElementById('quota-status')
    const quotaInfo = document.getElementById('quota-info')
    
    if (quotaStatus) {
      quotaStatus.classList.add('hidden')
    }
    
    if (quotaInfo) {
      quotaInfo.textContent = ''
    }
  }

  // Form submits normally
}