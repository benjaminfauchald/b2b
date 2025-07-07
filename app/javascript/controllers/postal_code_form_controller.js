import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="postal-code-form"
export default class extends Controller {
  static targets = ["customInput", "preview", "previewText"]
  static values = { updateUrl: String }

  connect() {
    this.updatePreview()
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
      return
    }

    const batchText = data.batch_size < data.count ? `top ${data.batch_size}` : `all ${data.count}`
    
    if (data.revenue_range) {
      const text = `${data.count} companies found. Will process ${batchText} (revenue range: ${data.revenue_range.lowest} - ${data.revenue_range.highest})`
      this.previewTextTarget.textContent = text
    } else {
      this.previewTextTarget.textContent = `${data.count} companies found. Will process ${batchText}`
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

  submit(event) {
    const postalCode = this.getPostalCode()
    if (!postalCode) {
      event.preventDefault()
      alert('Please select or enter a postal code')
      return
    }

    // Set the correct postal code value for submission
    const hiddenInput = document.createElement('input')
    hiddenInput.type = 'hidden'
    hiddenInput.name = 'postal_code'
    hiddenInput.value = postalCode
    event.target.appendChild(hiddenInput)
  }
}