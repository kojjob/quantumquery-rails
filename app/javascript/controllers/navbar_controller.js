import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["mobileMenu", "menuButton"]
  
  connect() {
    // Ensure mobile menu is hidden by default
    this.hideMobileMenu()
  }
  
  toggleMenu() {
    if (this.mobileMenuTarget.classList.contains('hidden')) {
      this.showMobileMenu()
    } else {
      this.hideMobileMenu()
    }
  }
  
  showMobileMenu() {
    // Remove hidden class and add animation
    this.mobileMenuTarget.classList.remove('hidden')
    this.mobileMenuTarget.classList.add('animate-fade-in-down')
    
    // Update button icon to X
    this.updateMenuButtonIcon(true)
    
    // Add event listener to close menu when clicking outside
    document.addEventListener('click', this.handleOutsideClick.bind(this))
  }
  
  hideMobileMenu() {
    // Add hidden class and remove animation
    this.mobileMenuTarget.classList.add('hidden')
    this.mobileMenuTarget.classList.remove('animate-fade-in-down')
    
    // Update button icon to hamburger
    this.updateMenuButtonIcon(false)
    
    // Remove event listener
    document.removeEventListener('click', this.handleOutsideClick.bind(this))
  }
  
  handleOutsideClick(event) {
    // Close menu if clicking outside navbar
    if (!this.element.contains(event.target)) {
      this.hideMobileMenu()
    }
  }
  
  updateMenuButtonIcon(isOpen) {
    if (this.hasMenuButtonTarget) {
      if (isOpen) {
        // Show X icon
        this.menuButtonTarget.innerHTML = `
          <svg class="h-6 w-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
          </svg>
        `
      } else {
        // Show hamburger icon
        this.menuButtonTarget.innerHTML = `
          <svg class="h-6 w-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16"></path>
          </svg>
        `
      }
    }
  }
  
  // Close menu when window is resized to desktop
  disconnect() {
    document.removeEventListener('click', this.handleOutsideClick.bind(this))
  }
}