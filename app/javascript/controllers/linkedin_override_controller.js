import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.checkbox = this.element.querySelector('#use-low-confidence-linkedin')
    if (this.checkbox) {
      this.checkbox.addEventListener('change', this.handleCheckboxChange.bind(this))
    }
  }

  disconnect() {
    if (this.checkbox) {
      this.checkbox.removeEventListener('change', this.handleCheckboxChange.bind(this))
    }
  }

  handleCheckboxChange(event) {
    const checkbox = event.target
    const companyId = checkbox.dataset.companyId
    const linkedinUrl = checkbox.dataset.linkedinUrl
    
    if (checkbox.checked) {
      // Update the company's linkedin_url via AJAX
      this.updateLinkedInUrl(companyId, linkedinUrl)
    } else {
      // Clear the linkedin_url if unchecked
      this.updateLinkedInUrl(companyId, '')
    }
  }

  updateLinkedInUrl(companyId, linkedinUrl) {
    const csrfToken = document.querySelector('[name="csrf-token"]').content
    
    fetch(`/companies/${companyId}`, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': csrfToken,
        'Accept': 'application/json'
      },
      credentials: 'same-origin',
      body: JSON.stringify({
        company: {
          linkedin_url: linkedinUrl
        }
      })
    })
    .then(response => {
      if (!response.ok) {
        throw new Error('Failed to update LinkedIn URL')
      }
      return response.json()
    })
    .then(data => {
      // Reload the page to reflect changes
      window.location.reload()
    })
    .catch(error => {
      console.error('Error updating LinkedIn URL:', error)
      alert('Failed to update LinkedIn URL. Please try again.')
      // Uncheck the checkbox on error
      this.checkbox.checked = false
    })
  }
}