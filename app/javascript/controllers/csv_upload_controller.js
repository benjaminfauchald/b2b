import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "dropZone", "fileInput", "progress", "progressBar", "progressText",
    "fileInfo", "fileName", "fileSize", "errors", "errorMessage"
  ]

  connect() {
    console.log('CSV Upload controller connected!')
    this.maxFileSize = 10 * 1024 * 1024 // 10MB in bytes
    this.allowedTypes = ['text/csv', 'application/csv', 'text/plain']
    
    // Test if all targets are available
    console.log('Drop zone target:', this.hasDropZoneTarget)
    console.log('File input target:', this.hasFileInputTarget)
  }

  openFileSelector() {
    console.log('Opening file selector...')
    this.fileInputTarget.click()
  }

  handleDragOver(event) {
    event.preventDefault()
    event.stopPropagation()
    console.log('Drag over detected')
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
    console.log('File dropped!')
    
    this.dropZoneTarget.classList.remove('border-blue-400', 'bg-blue-50', 'dark:bg-blue-900/20')
    
    const files = event.dataTransfer.files
    console.log('Dropped files:', files.length)
    if (files.length > 0) {
      try {
        this.fileInputTarget.files = files
        this.validateFile()
      } catch (error) {
        console.error('Error setting files:', error)
        // Fallback: create new FileList
        const dt = new DataTransfer()
        dt.items.add(files[0])
        this.fileInputTarget.files = dt.files
        this.validateFile()
      }
    }
  }

  validateFile() {
    const file = this.fileInputTarget.files[0]
    
    if (!file) {
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
      this.showError(`File size (${this.formatFileSize(file.size)}) exceeds the maximum allowed size (10MB).`)
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
      
      // Basic CSV validation
      if (content.trim().length === 0) {
        this.showError('The uploaded file is empty.')
        this.clearFileInput()
        return
      }

      // Check for required header
      const firstLine = content.split('\n')[0]
      if (!firstLine.toLowerCase().includes('domain')) {
        this.showError('CSV file must contain a "domain" column header.')
        this.clearFileInput()
        return
      }

      // File is valid
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
  }

  formatFileSize(bytes) {
    if (bytes === 0) return '0 Bytes'
    
    const k = 1024
    const sizes = ['Bytes', 'KB', 'MB', 'GB']
    const i = Math.floor(Math.log(bytes) / Math.log(k))
    
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
  }

  // Handle form submission with progress
  beforeSubmit(event) {
    if (this.fileInputTarget.files.length === 0) {
      event.preventDefault()
      this.showError('Please select a CSV file before uploading.')
      return false
    }

    this.showProgress()
    this.hideErrors()
    this.hideFileInfo()
    
    return true
  }
}