import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="dropdown"
export default class extends Controller {
  static targets = [ "menu" ]

  connect() {
    this.menuTarget.classList.add("hidden")
  }

  toggle(event) {
    event.stopPropagation()
    this.menuTarget.classList.toggle("hidden")
  }

  hide() {
    if (!this.menuTarget.classList.contains("hidden")) {
      this.menuTarget.classList.add("hidden")
    }
  }
}