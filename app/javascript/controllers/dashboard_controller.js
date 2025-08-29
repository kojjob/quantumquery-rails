import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["grid", "editToggle", "addButton", "modal", "widget"]
  
  connect() {
    this.editMode = false
    this.setupRefreshInterval()
  }
  
  disconnect() {
    if (this.refreshInterval) {
      clearInterval(this.refreshInterval)
    }
  }
  
  toggleEditMode() {
    this.editMode = !this.editMode
    this.gridTarget.dataset.editMode = this.editMode
    
    if (this.editMode) {
      this.editToggleTarget.classList.add("bg-purple-600", "text-white")
      this.editToggleTarget.classList.remove("border-gray-300", "text-gray-700")
      this.addButtonTarget.classList.remove("hidden")
      this.enableWidgetEditing()
    } else {
      this.editToggleTarget.classList.remove("bg-purple-600", "text-white")
      this.editToggleTarget.classList.add("border-gray-300", "text-gray-700")
      this.addButtonTarget.classList.add("hidden")
      this.disableWidgetEditing()
      this.saveLayout()
    }
  }
  
  enableWidgetEditing() {
    this.widgetTargets.forEach(widget => {
      widget.classList.add("cursor-move")
      widget.querySelector(".edit-widget")?.classList.remove("hidden")
      widget.querySelector(".remove-widget")?.classList.remove("hidden")
      widget.querySelector(".resize-handle")?.classList.remove("hidden")
    })
  }
  
  disableWidgetEditing() {
    this.widgetTargets.forEach(widget => {
      widget.classList.remove("cursor-move")
      widget.querySelector(".edit-widget")?.classList.add("hidden")
      widget.querySelector(".remove-widget")?.classList.add("hidden")
      widget.querySelector(".resize-handle")?.classList.add("hidden")
    })
  }
  
  showAddModal() {
    this.modalTarget.classList.remove("hidden")
  }
  
  hideAddModal() {
    this.modalTarget.classList.add("hidden")
  }
  
  async addWidget() {
    const widgetType = document.getElementById("widget-type-select").value
    const title = document.getElementById("widget-title-input").value
    const width = document.getElementById("widget-width-input").value
    const height = document.getElementById("widget-height-input").value
    
    const dashboardId = this.gridTarget.closest("[data-dashboard-id]").dataset.dashboardId
    
    const response = await fetch(`/dashboards/${dashboardId}/add_widget`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
      },
      body: JSON.stringify({
        widget: {
          widget_type: widgetType,
          title: title,
          width: parseInt(width),
          height: parseInt(height),
          row: 0,
          col: 0,
          config: {}
        }
      })
    })
    
    if (response.ok) {
      window.location.reload()
    }
  }
  
  async removeWidget(event) {
    const widgetId = event.currentTarget.dataset.widgetId
    const dashboardId = this.gridTarget.closest("[data-dashboard-id]").dataset.dashboardId
    
    if (confirm("Are you sure you want to remove this widget?")) {
      const response = await fetch(`/dashboards/${dashboardId}/remove_widget/${widgetId}`, {
        method: "DELETE",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        }
      })
      
      if (response.ok) {
        const widget = document.querySelector(`[data-widget-id="${widgetId}"]`)
        widget.remove()
      }
    }
  }
  
  async refreshWidget(event) {
    const widgetId = event.currentTarget.dataset.widgetId
    const dashboardId = this.gridTarget.closest("[data-dashboard-id]").dataset.dashboardId
    
    const response = await fetch(`/dashboards/${dashboardId}/refresh_widget/${widgetId}`, {
      headers: {
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
      }
    })
    
    if (response.ok) {
      const data = await response.json()
      // Update widget content with new data
      const widget = document.querySelector(`[data-widget-id="${widgetId}"]`)
      const contentDiv = widget.querySelector(".widget-content")
      contentDiv.dataset.widgetData = JSON.stringify(data.data)
      // Optionally trigger a re-render of the widget
    }
  }
  
  async saveLayout() {
    const widgets = []
    this.widgetTargets.forEach(widget => {
      const style = widget.style
      const gridColumn = style.gridColumn || ""
      const gridRow = style.gridRow || ""
      
      // Parse grid position from style
      const colMatch = gridColumn.match(/span (\d+)/)
      const rowMatch = gridRow.match(/span (\d+)/)
      const colStartMatch = style.gridColumnStart.match(/(\d+)/)
      const rowStartMatch = style.gridRowStart.match(/(\d+)/)
      
      widgets.push({
        id: widget.dataset.widgetId,
        width: colMatch ? parseInt(colMatch[1]) : 3,
        height: rowMatch ? parseInt(rowMatch[1]) : 2,
        col: colStartMatch ? parseInt(colStartMatch[1]) - 1 : 0,
        row: rowStartMatch ? parseInt(rowStartMatch[1]) - 1 : 0
      })
    })
    
    const dashboardId = this.gridTarget.closest("[data-dashboard-id]").dataset.dashboardId
    
    await fetch(`/dashboards/${dashboardId}/update_layout`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
      },
      body: JSON.stringify({ widgets })
    })
  }
  
  setupRefreshInterval() {
    // Auto-refresh widgets every 30 seconds
    this.refreshInterval = setInterval(() => {
      if (!this.editMode) {
        this.refreshAllWidgets()
      }
    }, 30000)
  }
  
  async refreshAllWidgets() {
    const refreshButtons = document.querySelectorAll(".refresh-widget")
    refreshButtons.forEach(button => {
      button.click()
    })
  }
  
  async refreshDashboard() {
    await this.refreshAllWidgets()
  }
}