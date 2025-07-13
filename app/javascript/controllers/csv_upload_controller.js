import { Controller } from "@hotwired/stimulus"

// Immediately log that the file is being loaded
console.log('[CSV Upload Controller] File is being loaded/imported');

export default class extends Controller {
  static targets = [
    "dropZone", "fileInput", "progress", "progressBar", "progressText",
    "fileInfo", "fileName", "fileSize", "errors", "errorMessage", "submitButton"
  ]
  
  static values = { 
    progressUrl: String 
  }

  connect() {
    console.log('CSV Upload Controller connected')
    console.log('Available methods:', Object.getOwnPropertyNames(Object.getPrototypeOf(this)))
    this.maxFileSize = 50 * 1024 * 1024 // 50MB in bytes
    this.allowedTypes = ['text/csv', 'application/csv', 'text/plain']
    
    // Disable submit button initially - use setTimeout to ensure DOM is ready
    setTimeout(() => {
      if (this.hasSubmitButtonTarget) {
        console.log('Disabling submit button:', this.submitButtonTarget)
        this.submitButtonTarget.disabled = true
        this.submitButtonTarget.classList.add('opacity-50', 'cursor-not-allowed')
      }
    }, 0)
  }

  openFileSelector() {
    this.fileInputTarget.click()
  }

  handleKeyDown(event) {
    // Handle Enter and Space keys
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault()
      this.openFileSelector()
    }
  }

  handleDragOver(event) {
    event.preventDefault()
    event.stopPropagation()
    this.dropZoneTarget.classList.add('border-blue-400', 'bg-blue-50', 'dark:bg-blue-900/20')
  }

  handleDragLeave(event) {
    event.preventDefault()
    event.stopPropagation()
    this.dropZoneTarget.classList.remove('border-blue-400', 'bg-blue-50', 'dark:bg-blue-900/20')
  }

  handleDrop(event) {
    event.preventDefault()
    event.stopPropagation()
    
    this.dropZoneTarget.classList.remove('border-blue-400', 'bg-blue-50', 'dark:bg-blue-900/20')
    
    const files = event.dataTransfer.files
    if (files.length > 0) {
      try {
        this.fileInputTarget.files = files
        this.validateFile()
      } catch (error) {
        // Fallback: create new FileList
        const dt = new DataTransfer()
        dt.items.add(files[0])
        this.fileInputTarget.files = dt.files
        this.validateFile()
      }
    }
  }

  validateFile() {
    console.log('validateFile called')
    console.log('File input:', this.fileInputTarget)
    console.log('Files:', this.fileInputTarget.files)
    const file = this.fileInputTarget.files[0]
    console.log('Selected file:', file)
    
    if (!file) {
      console.log('No file selected')
      this.hideAllFeedback()
      return
    }

    // Validate file type
    if (!this.isValidFileType(file)) {
      this.showError('Please upload a CSV file. Allowed types: .csv')
      this.clearFileInput()
      return
    }

    // Validate file size
    if (file.size > this.maxFileSize) {
      this.showError(`File size (${this.formatFileSize(file.size)}) exceeds the maximum allowed size (50MB).`)
      this.clearFileInput()
      return
    }

    // Validate file content (basic check)
    this.validateFileContent(file)
  }

  validateFileContent(file) {
    const reader = new FileReader()
    
    reader.onload = (e) => {
      const content = e.target.result
      console.log('File content (first 200 chars):', content.substring(0, 200))
      
      // Basic CSV validation
      if (content.trim().length === 0) {
        console.log('File is empty, clearing input')
        this.showError('The uploaded file is empty.')
        this.clearFileInput()
        return
      }

      // Check for required headers based on the page context
      const firstLine = content.split('\n')[0].trim()
      console.log('First line of CSV:', firstLine)
      console.log('First line lowercase:', firstLine.toLowerCase())
      
      // Determine if we're on a domain import page or person import page
      const isDomainImport = window.location.pathname.includes('/domains/import')
      const isPersonImport = window.location.pathname.includes('/people/import')
      
      if (isDomainImport) {
        // Domain import validation
        console.log('Contains "domain"?', firstLine.toLowerCase().includes('domain'))
        
        // Handle domains that may end with a dot (like "se.")
        const domainWithoutTrailingDot = firstLine.endsWith('.') ? firstLine.slice(0, -1) : firstLine
        const domainRegex = /\.[a-zA-Z]{2,}$/
        const looksLikeDomain = domainRegex.test(domainWithoutTrailingDot) || domainWithoutTrailingDot === 'se' // Special case for TLD only
        console.log('Testing regex:', domainRegex)
        console.log('Testing against (without trailing dot):', JSON.stringify(domainWithoutTrailingDot))
        console.log('First line looks like domain?', looksLikeDomain)
        
        if (!firstLine.toLowerCase().includes('domain') && !looksLikeDomain) {
          console.log('Domain header not found and first line does not look like a domain, clearing input')
          this.showError('CSV file must contain a "domain" column header or start with valid domain names.')
          this.clearFileInput()
          return
        }
      } else if (isPersonImport) {
        // Person import validation - check for email header OR Phantom Buster format
        const hasEmailHeader = firstLine.toLowerCase().includes('email')
        const hasPhantomBusterHeaders = firstLine.toLowerCase().includes('profileurl') && 
                                        firstLine.toLowerCase().includes('fullname') &&
                                        firstLine.toLowerCase().includes('linkedinprofileurl')
        console.log('Contains "email"?', hasEmailHeader)
        console.log('Is Phantom Buster format?', hasPhantomBusterHeaders)
        
        if (!hasEmailHeader && !hasPhantomBusterHeaders) {
          console.log('Neither email header nor Phantom Buster format found, clearing input')
          console.log('First line headers:', firstLine)
          
          // Check if this might be a postal code or domain file
          const hasPostalHeaders = firstLine.toLowerCase().includes('postcode') || 
                                  firstLine.toLowerCase().includes('postal') ||
                                  firstLine.toLowerCase().includes('zip')
          const hasDomainHeaders = firstLine.toLowerCase().includes('domain')
          
          let errorMessage = 'CSV file must contain an "email" column header or be in Phantom Buster format for person imports.'
          
          if (hasPostalHeaders) {
            errorMessage += ' This appears to be a postal code file. Please use the Domain Import feature instead.'
          } else if (hasDomainHeaders) {
            errorMessage += ' This appears to be a domain file. Please use the Domain Import feature instead.'
          } else {
            errorMessage += ` Found headers: ${firstLine}`
          }
          
          this.showError(errorMessage)
          this.clearFileInput()
          return
        }
      } else {
        // Generic validation - accept any CSV with headers
        console.log('Generic CSV import - accepting file with headers')
        if (!firstLine.includes(',')) {
          this.showError('CSV file must contain comma-separated headers.')
          this.clearFileInput()
          return
        }
      }

      // File is valid
      console.log('File is valid, showing file info')
      this.showFileInfo(file)
      this.hideErrors()
    }

    reader.onerror = () => {
      this.showError('Error reading file. Please try again.')
      this.clearFileInput()
    }

    // Read first 1KB to validate headers
    const blob = file.slice(0, 1024)
    reader.readAsText(blob)
  }

  isValidFileType(file) {
    // Check MIME type
    if (this.allowedTypes.includes(file.type)) {
      return true
    }
    
    // Check file extension as fallback
    const fileName = file.name.toLowerCase()
    return fileName.endsWith('.csv')
  }

  showFileInfo(file) {
    this.fileNameTarget.textContent = file.name
    this.fileSizeTarget.textContent = this.formatFileSize(file.size)
    this.fileInfoTarget.classList.remove('hidden')
    this.enableSubmitButton()
  }

  showError(message) {
    this.errorMessageTarget.textContent = message
    this.errorsTarget.classList.remove('hidden')
    this.hideFileInfo()
  }

  hideErrors() {
    this.errorsTarget.classList.add('hidden')
  }

  hideFileInfo() {
    this.fileInfoTarget.classList.add('hidden')
  }

  hideProgress() {
    this.progressTarget.classList.add('hidden')
  }

  hideAllFeedback() {
    this.hideErrors()
    this.hideFileInfo()
    this.hideProgress()
  }

  showProgress() {
    this.progressTarget.classList.remove('hidden')
    this.progressBarTarget.style.width = '0%'
    this.progressTextTarget.textContent = 'Uploading...'
  }

  updateUploadProgress(percent) {
    this.progressBarTarget.style.width = `${percent}%`
    this.progressTextTarget.textContent = `Uploading... ${percent}%`
  }

  clearFileInput() {
    this.fileInputTarget.value = ''
    this.hideAllFeedback()
    this.disableSubmitButton()
  }

  formatFileSize(bytes) {
    if (bytes === 0) return '0 Bytes'
    
    const k = 1024
    const sizes = ['Bytes', 'KB', 'MB', 'GB']
    const i = Math.floor(Math.log(bytes) / Math.log(k))
    
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
  }

  enableSubmitButton() {
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = false
      this.submitButtonTarget.classList.remove('opacity-50', 'cursor-not-allowed')
    }
  }

  disableSubmitButton() {
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = true
      this.submitButtonTarget.classList.add('opacity-50', 'cursor-not-allowed')
    }
  }

  // Submit handler for form submission
  handleSubmit(event) {
    console.log('CSV Upload handleSubmit called', event)
    
    // Only validate that a file is selected
    if (!this.fileInputTarget.files || this.fileInputTarget.files.length === 0) {
      console.log('No files selected, preventing submission')
      event.preventDefault()
      this.showError('Please select a CSV file before uploading.')
      if (this.hasDropZoneTarget) {
        this.dropZoneTarget.focus()
      }
      return false
    }

    console.log('File validation passed, proceeding with form submission')

    // Get file size to determine if we'll need progress polling
    const file = this.fileInputTarget.files[0]
    const fileSizeMB = file.size / (1024 * 1024)
    const largeFileThreshold = 5.0 // MB - matches server-side threshold
    
    console.log(`File size: ${fileSizeMB.toFixed(2)} MB`)
    console.log(`Large file threshold: ${largeFileThreshold} MB`)
    console.log(`Will use: ${fileSizeMB > largeFileThreshold ? 'BACKGROUND PROCESSING' : 'SYNCHRONOUS PROCESSING'}`)

    // Update UI to show submission is in progress
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.value = "Processing..."
      this.submitButtonTarget.disabled = true
      this.submitButtonTarget.classList.add('opacity-50', 'cursor-not-allowed')
    }
    
    this.showProgress()
    
    if (fileSizeMB > largeFileThreshold) {
      // Large file - will be processed in background, start polling
      this.updateProgress(0, 'Uploading file...')
      console.log('Large file detected - will start progress polling after form submission')
      
      // Start progress polling after a delay to allow form submission and job queuing
      setTimeout(() => {
        this.startProgressPolling()
      }, 2000)
    } else {
      // Small file - will be processed synchronously, just show uploading message
      this.updateProgress(50, 'Processing file...')
      console.log('Small file detected - will be processed synchronously (no polling needed)')
    }
    
    // Allow form to submit normally
    console.log('Allowing form to submit normally')
    return true
  }

  startProgressPolling() {
    console.log('Starting progress polling...')
    this.startTime = Date.now() // Reset start time for tracking
    
    this.progressPoller = setInterval(() => {
      this.fetchProgress()
    }, 2000) // Poll every 2 seconds (reduced frequency)
    
    // Set a maximum polling time (5 minutes) to prevent infinite polling
    this.maxPollingTime = setTimeout(() => {
      this.stopProgressPolling()
      console.log('Progress polling stopped due to timeout (5 minutes)')
      this.updateProgress(100, 'Import may have completed (timeout)')
    }, 300000) // 5 minutes
  }

  stopProgressPolling() {
    if (this.progressPoller) {
      clearInterval(this.progressPoller)
      this.progressPoller = null
    }
    if (this.maxPollingTime) {
      clearTimeout(this.maxPollingTime)
      this.maxPollingTime = null
    }
  }

  async fetchProgress() {
    try {
      // Use dynamic progress URL or fall back to default
      const progressUrl = this.progressUrlValue || '/people/import_progress'
      console.log('Fetching progress from:', progressUrl)
      
      const response = await fetch(progressUrl, {
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })
      
      if (response.ok) {
        const data = await response.json()
        console.log('Progress data received:', data)
        
        if (data.status === 'in_progress') {
          const percent = data.percent || Math.round((data.current / data.total) * 100) || 0
          const message = data.message || `Processing ${data.current}/${data.total} records...`
          this.updateProgress(percent, message)
          
          console.log(`Progress: ${percent}% - ${message}`)
        } else if (data.status === 'complete') {
          // Import completed - stop polling and redirect
          console.log('Import completed - preparing redirect')
          this.updateProgress(100, 'Import completed!')
          this.stopProgressPolling()
          
          // Redirect to results page after a short delay
          console.log('Redirecting to import results page...')
          setTimeout(() => {
            const redirectUrl = '/people/import_results'
            console.log('Redirecting to:', redirectUrl)
            window.location.href = redirectUrl
          }, 2000)
        } else if (data.status === 'not_found') {
          // Import might be complete or not started yet
          console.log('No progress data found - import may not have started yet')
          // If we've been polling for more than 30 seconds without finding data, stop
          if (!this.startTime) this.startTime = Date.now()
          if (Date.now() - this.startTime > 30000) {
            console.log('Stopping progress polling - no data found for 30 seconds')
            this.stopProgressPolling()
            this.updateProgress(100, 'Import may have completed')
          }
        }
      } else {
        console.error('Progress fetch failed with status:', response.status)
      }
    } catch (error) {
      console.error('Failed to fetch progress:', error)
      // Don't stop polling on network errors, just log them
    }
  }

  updateProgress(percent, message = null) {
    if (this.hasProgressBarTarget) {
      this.progressBarTarget.style.width = `${percent}%`
    }
    if (this.hasProgressTextTarget) {
      this.progressTextTarget.textContent = message || `Processing... ${percent}%`
    }
  }

  disconnect() {
    // Clean up polling when controller is disconnected
    this.stopProgressPolling()
  }
}

// Controller class ends here - already exported above