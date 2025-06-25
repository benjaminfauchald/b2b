import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { 
    url: String,
    interval: { type: Number, default: 3000 } // 3 second default
  }

  connect() {
    this.pollCount = 0
    this.lastUpdateTime = Date.now()
    this.startPolling()
    
    // Listen for immediate update events
    this.boundUpdateHandler = this.handleImmediateUpdate.bind(this)
    document.addEventListener('service-stats:update', this.boundUpdateHandler)
  }

  disconnect() {
    this.stopPolling()
    document.removeEventListener('service-stats:update', this.boundUpdateHandler)
  }

  handleImmediateUpdate(event) {
    // Trigger immediate poll when stats change
    this.poll()
    
    // Temporarily increase polling frequency for 30 seconds after an update
    this.stopPolling()
    this.startFrequentPolling()
  }

  startPolling() {
    this.poll()
    this.timer = setInterval(() => {
      this.poll()
    }, this.intervalValue)
  }

  startFrequentPolling() {
    // Poll every 1 second for 30 seconds after an update
    this.poll()
    this.frequentTimer = setInterval(() => {
      this.poll()
    }, 1000)

    // Return to normal polling after 30 seconds
    setTimeout(() => {
      this.stopFrequentPolling()
      this.startPolling()
    }, 30000)
  }

  stopPolling() {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
  }

  stopFrequentPolling() {
    if (this.frequentTimer) {
      clearInterval(this.frequentTimer)
      this.frequentTimer = null
    }
  }

  async poll() {
    try {
      const response = await fetch(this.urlValue, {
        headers: {
          'Accept': 'text/vnd.turbo-stream.html',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })
      
      if (response.ok) {
        const html = await response.text()
        Turbo.renderStreamMessage(html)
        this.pollCount++
        this.lastUpdateTime = Date.now()
        
        // Add visual feedback for active updates
        this.showUpdateIndicator()
      } else {
        console.warn('Service stats request failed:', response.status)
      }
    } catch (error) {
      console.error('Error fetching service stats:', error)
    }
  }

  showUpdateIndicator() {
    // Add a subtle visual indicator that stats are updating
    const indicator = document.querySelector('.service-stats-indicator')
    if (indicator) {
      indicator.classList.add('animate-pulse')
      setTimeout(() => {
        indicator.classList.remove('animate-pulse')
      }, 200)
    }
  }
}