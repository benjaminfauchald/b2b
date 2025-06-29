import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "button"]
  
  connect() {
    this.menuTarget = document.getElementById('mobile-menu')
    this.isOpen = false
  }
  
  toggle() {
    this.isOpen = !this.isOpen
    
    if (this.isOpen) {
      this.menuTarget.classList.remove('hidden')
      this.buttonTarget.setAttribute('aria-expanded', 'true')
    } else {
      this.menuTarget.classList.add('hidden')
      this.buttonTarget.setAttribute('aria-expanded', 'false')
    }
  }
}