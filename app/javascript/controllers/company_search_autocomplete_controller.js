// ============================================================================
// Company Search Autocomplete Controller
// ============================================================================
// Feature tracked by IDM: app/services/feature_memories/company_search_autocomplete.rb
// ============================================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "dropdown", "noResults"]
  static values = { 
    url: String,
    minCharacters: { type: Number, default: 2 },
    debounceDelay: { type: Number, default: 300 },
    maxSuggestions: { type: Number, default: 10 }
  }

  connect() {
    this.currentRequest = null
    this.isOpen = false
    this.selectedIndex = -1
    this.suggestions = []
    
    // Bind methods for event handling
    this.boundHandleDocumentClick = this.handleDocumentClick.bind(this)
    this.boundHandleKeydown = this.handleKeydown.bind(this)
    
    // Add global event listeners
    document.addEventListener('click', this.boundHandleDocumentClick)
    this.inputTarget.addEventListener('keydown', this.boundHandleKeydown)
  }

  disconnect() {
    this.cancelPendingRequest()
    document.removeEventListener('click', this.boundHandleDocumentClick)
    this.inputTarget.removeEventListener('keydown', this.boundHandleKeydown)
  }

  // Handle input events with debouncing
  onInput(event) {
    const query = event.target.value.trim()
    
    // Clear any pending requests
    this.cancelPendingRequest()
    
    // Hide dropdown if query is too short
    if (query.length < this.minCharactersValue) {
      this.hideDropdown()
      return
    }
    
    // Debounce the search request
    this.debounceTimer = setTimeout(() => {
      this.performSearch(query)
    }, this.debounceDelayValue)
  }

  // Perform the actual search request
  async performSearch(query) {
    try {
      // Cancel any pending request
      this.cancelPendingRequest()
      
      // Create AbortController for request cancellation
      const controller = new AbortController()
      this.currentRequest = controller
      
      const url = new URL(this.urlValue, window.location.origin)
      url.searchParams.set('q', query)
      url.searchParams.set('limit', this.maxSuggestionsValue)
      
      const response = await fetch(url, {
        signal: controller.signal,
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })
      
      if (response.ok) {
        const data = await response.json()
        this.displaySuggestions(data.suggestions || [])
      } else {
        console.warn('Autocomplete request failed:', response.status)
        this.hideDropdown()
      }
    } catch (error) {
      if (error.name !== 'AbortError') {
        console.error('Autocomplete search error:', error)
        this.hideDropdown()
      }
    } finally {
      this.currentRequest = null
    }
  }

  // Display search suggestions
  displaySuggestions(suggestions) {
    this.suggestions = suggestions
    this.selectedIndex = -1
    
    if (suggestions.length === 0) {
      this.showNoResults()
      return
    }
    
    // Build dropdown HTML
    const dropdownHTML = suggestions.map((suggestion, index) => {
      return `
        <div class="suggestion-item px-4 py-2 cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-700 ${
          index === this.selectedIndex ? 'bg-blue-100 dark:bg-blue-900' : ''
        }" 
             data-index="${index}"
             data-action="click->company-search-autocomplete#selectSuggestion">
          <div class="font-medium text-gray-900 dark:text-white">${this.escapeHtml(suggestion.company_name)}</div>
          ${suggestion.registration_number ? `<div class="text-sm text-gray-600 dark:text-gray-400">${this.escapeHtml(suggestion.registration_number)}</div>` : ''}
        </div>
      `
    }).join('')
    
    this.dropdownTarget.innerHTML = dropdownHTML
    this.showDropdown()
  }

  // Show "No results found" message
  showNoResults() {
    this.dropdownTarget.innerHTML = `
      <div class="px-4 py-2 text-gray-600 dark:text-gray-400 text-sm">
        No companies found
      </div>
    `
    this.showDropdown()
  }

  // Show the dropdown
  showDropdown() {
    this.dropdownTarget.classList.remove('hidden')
    this.isOpen = true
  }

  // Hide the dropdown
  hideDropdown() {
    this.dropdownTarget.classList.add('hidden')
    this.isOpen = false
    this.selectedIndex = -1
    this.suggestions = []
  }

  // Handle suggestion selection
  selectSuggestion(event) {
    const index = parseInt(event.currentTarget.dataset.index)
    this.selectSuggestionByIndex(index)
  }

  // Select suggestion by index
  selectSuggestionByIndex(index) {
    if (index >= 0 && index < this.suggestions.length) {
      const suggestion = this.suggestions[index]
      this.inputTarget.value = suggestion.company_name
      this.hideDropdown()
      
      // Trigger form submission or custom event
      this.inputTarget.form?.requestSubmit()
    }
  }

  // Handle keyboard navigation
  handleKeydown(event) {
    if (!this.isOpen) return
    
    switch (event.key) {
      case 'ArrowDown':
        event.preventDefault()
        this.moveSelection(1)
        break
      case 'ArrowUp':
        event.preventDefault()
        this.moveSelection(-1)
        break
      case 'Enter':
        event.preventDefault()
        if (this.selectedIndex >= 0) {
          this.selectSuggestionByIndex(this.selectedIndex)
        }
        break
      case 'Escape':
        this.hideDropdown()
        break
    }
  }

  // Move selection up or down
  moveSelection(direction) {
    const maxIndex = this.suggestions.length - 1
    
    if (direction > 0) {
      // Move down
      this.selectedIndex = this.selectedIndex < maxIndex ? this.selectedIndex + 1 : 0
    } else {
      // Move up
      this.selectedIndex = this.selectedIndex > 0 ? this.selectedIndex - 1 : maxIndex
    }
    
    this.updateSelectionHighlight()
  }

  // Update visual selection highlight
  updateSelectionHighlight() {
    const items = this.dropdownTarget.querySelectorAll('.suggestion-item')
    
    items.forEach((item, index) => {
      if (index === this.selectedIndex) {
        item.classList.add('bg-blue-100', 'dark:bg-blue-900')
        item.classList.remove('hover:bg-gray-100', 'dark:hover:bg-gray-700')
      } else {
        item.classList.remove('bg-blue-100', 'dark:bg-blue-900')
        item.classList.add('hover:bg-gray-100', 'dark:hover:bg-gray-700')
      }
    })
  }

  // Handle clicks outside the component
  handleDocumentClick(event) {
    if (!this.element.contains(event.target)) {
      this.hideDropdown()
    }
  }

  // Cancel any pending search request
  cancelPendingRequest() {
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
      this.debounceTimer = null
    }
    
    if (this.currentRequest) {
      this.currentRequest.abort()
      this.currentRequest = null
    }
  }

  // Helper method to escape HTML
  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }
}