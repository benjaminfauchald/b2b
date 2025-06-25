import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { 
    url: String,
    interval: { type: Number, default: 1000 } // 1 second default
  }

  connect() {
    this.startPolling()
  }

  disconnect() {
    this.stopPolling()
  }

  startPolling() {
    this.poll()
    this.timer = setInterval(() => {
      this.poll()
    }, this.intervalValue)
  }

  stopPolling() {
    if (this.timer) {
      clearInterval(this.timer)
    }
  }

  async poll() {
    try {
      const response = await fetch(this.urlValue, {
        headers: {
          'Accept': 'text/vnd.turbo-stream.html'
        }
      })
      
      if (response.ok) {
        const html = await response.text()
        Turbo.renderStreamMessage(html)
      }
    } catch (error) {
      console.error('Error fetching service stats:', error)
    }
  }
}