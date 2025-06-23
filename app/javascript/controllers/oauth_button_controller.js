import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "loading"]

  handleClick(event) {
    // Show loading state
    this.contentTarget.classList.add("hidden")
    this.loadingTarget.classList.remove("hidden")
    
    // Disable the button to prevent double clicks
    this.element.setAttribute("disabled", "true")
    this.element.classList.add("opacity-50", "cursor-not-allowed")
    
    // Set a timeout to reset if OAuth doesn't redirect in time
    setTimeout(() => {
      this.resetButton()
    }, 10000) // 10 seconds timeout
  }

  resetButton() {
    this.contentTarget.classList.remove("hidden")
    this.loadingTarget.classList.add("hidden")
    this.element.removeAttribute("disabled")
    this.element.classList.remove("opacity-50", "cursor-not-allowed")
  }
}