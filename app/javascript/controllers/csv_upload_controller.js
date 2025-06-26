import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "dropZone", "fileInput", "progress", "progressBar", "progressText",
    "fileInfo", "fileName", "fileSize", "errors", "errorMessage", "submitButton"
  ]

  connect() {
    console.log('CSV Upload Controller connected')
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

      // Check for required header or if first line looks like a domain
      const firstLine = content.split('\n')[0].trim()
      console.log('First line of CSV:', firstLine)
      console.log('First line lowercase:', firstLine.toLowerCase())
      console.log('Contains "domain"?', firstLine.toLowerCase().includes('domain'))
      
      // Check if it has a header or if the first line looks like a domain
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

  updateProgress(percent) {
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

  // Handle form submission with progress
  beforeSubmit(event) {
    console.log('beforeSubmit called')
    console.log('Form event:', event)
    console.log('File input target:', this.fileInputTarget)
    console.log('Files:', this.fileInputTarget.files)
    console.log('Files length:', this.fileInputTarget.files?.length)
    
    if (!this.fileInputTarget.files || this.fileInputTarget.files.length === 0) {
      console.log('No files selected, preventing submission')
      event.preventDefault()
      event.stopPropagation()
      this.showError('Please select a CSV file before uploading.')
      // Focus on the drop zone for accessibility
      this.dropZoneTarget.focus()
      return false
    }

    this.showProgress()
    this.hideErrors()
    this.hideFileInfo()
    
    return true
  }
}