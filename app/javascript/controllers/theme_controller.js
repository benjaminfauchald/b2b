import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Check for saved theme preference or default to system preference
    const savedTheme = localStorage.getItem('theme')
    
    if (savedTheme) {
      // Use saved preference
      if (savedTheme === 'dark') {
        document.documentElement.classList.add('dark')
      } else {
        document.documentElement.classList.remove('dark')
      }
    } else {
      // Use system preference
      if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
        document.documentElement.classList.add('dark')
        localStorage.setItem('theme', 'dark')
      } else {
        document.documentElement.classList.remove('dark')
        localStorage.setItem('theme', 'light')
      }
    }
  }

  toggle() {
    const isDark = document.documentElement.classList.contains('dark')
    
    if (isDark) {
      document.documentElement.classList.remove('dark')
      localStorage.setItem('theme', 'light')
    } else {
      document.documentElement.classList.add('dark')
      localStorage.setItem('theme', 'dark')
    }
  }
}