import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="postal-code-form"
export default class extends Controller {
  static targets = ["customInput", "preview", "previewText"]
  static values = { updateUrl: String }

  connect() {
    this.updatePreview()
    
    // Listen for successful form submissions
    this.element.addEventListener('turbo:submit-end', this.handleFormSubmission.bind(this))
  }

  handleFormSubmission(event) {
    // Check if the form submission was successful
    if (event.detail.success) {
      // Dispatch event to trigger immediate service stats update
      const serviceStatsEvent = new CustomEvent('service-stats:update')
      document.dispatchEvent(serviceStatsEvent)
    }
  }

  updatePreview() {
    const postalCode = this.getPostalCode()
    const batchSize = this.getBatchSize()
    
    // Show/hide custom input based on postal code selection
    const postalCodeSelect = this.element.querySelector('select[name="postal_code"]')
    if (postalCodeSelect && postalCodeSelect.value === "") {
      this.customInputTarget.classList.remove("hidden")
    } else {
      this.customInputTarget.classList.add("hidden")
    }

    if (postalCode) {
      this.fetchPreviewData(postalCode, batchSize)
    } else {
      this.previewTextTarget.textContent = "Enter a postal code to see preview"
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
      return
    }

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

  updateButtonState(enabled, buttonText) {
    const submitButton = this.element.querySelector('input[type="submit"], button[type="submit"]')
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
    const postalCodeSelect = this.element.querySelector('select[name="postal_code"]')
    const customInput = this.element.querySelector('input[name="custom_postal_code"]')
    
    if (postalCodeSelect && postalCodeSelect.value) {
      return postalCodeSelect.value
    } else if (customInput && customInput.value) {
      return customInput.value
    }
    
    return null
  }

  getBatchSize() {
    const batchSizeSelect = this.element.querySelector('select[name="batch_size"]')
    return batchSizeSelect ? parseInt(batchSizeSelect.value) : 100
  }

  // Form submits normally
}