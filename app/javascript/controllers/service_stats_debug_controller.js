import { Controller } from "@hotwired/stimulus"

// Debug controller to understand the flickering issue
export default class extends Controller {
  static values = { pageName: String }
  
  connect() {
    console.log(`[ServiceStatsDebug] Connected on ${this.pageNameValue} page`)
    
    // Monitor Turbo Stream events
    document.addEventListener('turbo:before-stream-render', this.beforeStreamRender.bind(this))
    document.addEventListener('turbo:render', this.onRender.bind(this))
    
    // Log all turbo frames on the page
    this.logAllFrames()
  }
  
  disconnect() {
    document.removeEventListener('turbo:before-stream-render', this.beforeStreamRender)
    document.removeEventListener('turbo:render', this.onRender)
  }
  
  beforeStreamRender(event) {
    const { target, detail } = event
    console.log(`[ServiceStatsDebug] Turbo Stream incoming on ${this.pageNameValue}:`, {
      action: detail.newStream?.action,
      target: detail.newStream?.target,
      content: detail.newStream?.templateContent?.textContent?.substring(0, 100) + '...'
    })
  }
  
  onRender(event) {
    console.log(`[ServiceStatsDebug] Turbo rendered on ${this.pageNameValue}`)
  }
  
  logAllFrames() {
    const frames = document.querySelectorAll('turbo-frame')
    console.log(`[ServiceStatsDebug] Turbo frames on ${this.pageNameValue}:`)
    frames.forEach(frame => {
      console.log(`  - ${frame.id}`)
    })
  }
}