import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Restore scroll position if available
    const scrollY = sessionStorage.getItem('scrollPosition')
    if (scrollY) {
      window.scrollTo(0, parseInt(scrollY))
      sessionStorage.removeItem('scrollPosition')
    }
  }

  savePosition() {
    // Save current scroll position before form submission
    sessionStorage.setItem('scrollPosition', window.scrollY)
  }
}