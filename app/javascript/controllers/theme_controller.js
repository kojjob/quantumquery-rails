import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["icon"]
  
  connect() {
    console.log('Theme controller connected')
    // Check for saved theme preference or default to 'light'
    const currentTheme = localStorage.getItem('theme') || window.currentTheme || 'light'
    console.log('Current theme:', currentTheme)
    this.setTheme(currentTheme)
    
    // Update icon immediately on connect
    this.updateIcon(currentTheme)
  }
  
  toggle() {
    console.log('Theme toggle clicked')
    const isDarkMode = document.documentElement.classList.contains('dark')
    const newTheme = isDarkMode ? 'light' : 'dark'
    console.log('Toggling to:', newTheme)
    this.setTheme(newTheme)
  }
  
  setTheme(theme) {
    // Save preference
    localStorage.setItem('theme', theme)
    
    // Add or remove dark class from html element (TailwindCSS approach)
    if (theme === 'dark') {
      document.documentElement.classList.add('dark')
    } else {
      document.documentElement.classList.remove('dark')
    }
    
    // Update button appearance
    this.updateIcon(theme)
  }
  
  updateIcon(theme) {
    if (this.hasIconTarget) {
      if (theme === 'dark') {
        // Show sun icon (switch to light mode)
        this.iconTarget.innerHTML = `
          <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z"></path>
          </svg>
        `
      } else {
        // Show moon icon (switch to dark mode)
        this.iconTarget.innerHTML = `
          <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20.354 15.354A9 9 0 018.646 3.646 9.003 9.003 0 0012 21a9.003 9.003 0 008.354-5.646z"></path>
          </svg>
        `
      }
    }
  }
}