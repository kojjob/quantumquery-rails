import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Add smooth scrolling to all anchor links
    this.element.addEventListener('click', this.handleClick.bind(this))
  }

  disconnect() {
    this.element.removeEventListener('click', this.handleClick.bind(this))
  }

  handleClick(event) {
    const link = event.target.closest('a[href^="#"]')
    
    if (link) {
      event.preventDefault()
      const targetId = link.getAttribute('href')
      
      if (targetId === '#') {
        // Scroll to top
        window.scrollTo({
          top: 0,
          behavior: 'smooth'
        })
      } else {
        const targetElement = document.querySelector(targetId)
        
        if (targetElement) {
          targetElement.scrollIntoView({
            behavior: 'smooth',
            block: 'start'
          })
        }
      }
    }
  }

  // Method that can be called directly via data-action
  scrollTo(event) {
    event.preventDefault()
    const target = event.currentTarget
    const targetId = target.getAttribute('href')
    
    if (targetId && targetId.startsWith('#')) {
      const targetElement = document.querySelector(targetId)
      
      if (targetElement) {
        targetElement.scrollIntoView({
          behavior: 'smooth',
          block: 'start'
        })
      }
    }
  }
}