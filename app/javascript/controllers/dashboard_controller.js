import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["grid", "editToggle", "addButton", "modal", "widget", "timeRange", "loadingOverlay"]
  
  connect() {
    this.editMode = false
    this.setupRefreshInterval()
    this.setupEventListeners()
    this.currentTimeRange = "30days"
  }
  
  disconnect() {
    if (this.refreshInterval) {
      clearInterval(this.refreshInterval)
    }
  }
  
  setupEventListeners() {
    // Close modal when clicking outside
    if (this.hasModalTarget) {
      this.modalTarget.addEventListener('click', (e) => {
        if (e.target === this.modalTarget) {
          this.hideAddModal()
        }
      })
    }
    
    // Handle ESC key to close modal
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && this.hasModalTarget && !this.modalTarget.classList.contains('hidden')) {
        this.hideAddModal()
      }
    })
  }
  
  toggleEditMode() {
    this.editMode = !this.editMode
    this.gridTarget.dataset.editMode = this.editMode
    
    const editButton = this.editToggleTarget
    const editText = editButton.querySelector('span')
    
    if (this.editMode) {
      // Update button appearance for edit mode
      editButton.classList.remove('bg-white', 'dark:bg-slate-800', 'hover:bg-slate-50', 'dark:hover:bg-slate-700')
      editButton.classList.add('bg-teal-600', 'hover:bg-teal-700', 'text-white')
      if (editText) editText.textContent = 'Save Layout'
      
      // Show add button
      if (this.hasAddButtonTarget) {
        this.addButtonTarget.classList.remove('hidden')
      }
      
      this.enableWidgetEditing()
      this.showNotification('Edit mode enabled - Drag widgets to reposition', 'info')
    } else {
      // Update button appearance for view mode
      editButton.classList.add('bg-white', 'dark:bg-slate-800', 'hover:bg-slate-50', 'dark:hover:bg-slate-700')
      editButton.classList.remove('bg-teal-600', 'hover:bg-teal-700', 'text-white')
      if (editText) editText.textContent = 'Edit'
      
      // Hide add button
      if (this.hasAddButtonTarget) {
        this.addButtonTarget.classList.add('hidden')
      }
      
      this.disableWidgetEditing()
      this.saveLayout()
      this.showNotification('Layout saved successfully', 'success')
    }
  }
  
  enableWidgetEditing() {
    this.widgetTargets.forEach(widget => {
      widget.classList.add('cursor-move', 'hover:ring-2', 'hover:ring-teal-500')
      
      // Show edit and remove buttons
      const editBtn = widget.querySelector('.edit-widget')
      const removeBtn = widget.querySelector('.remove-widget')
      const resizeHandle = widget.querySelector('.resize-handle')
      
      if (editBtn) editBtn.classList.remove('hidden')
      if (removeBtn) removeBtn.classList.remove('hidden')
      if (resizeHandle) resizeHandle.classList.remove('hidden')
      
      // Make widget draggable
      this.makeWidgetDraggable(widget)
    })
  }
  
  disableWidgetEditing() {
    this.widgetTargets.forEach(widget => {
      widget.classList.remove('cursor-move', 'hover:ring-2', 'hover:ring-teal-500')
      
      // Hide edit and remove buttons
      const editBtn = widget.querySelector('.edit-widget')
      const removeBtn = widget.querySelector('.remove-widget')
      const resizeHandle = widget.querySelector('.resize-handle')
      
      if (editBtn) editBtn.classList.add('hidden')
      if (removeBtn) removeBtn.classList.add('hidden')
      if (resizeHandle) resizeHandle.classList.add('hidden')
      
      // Remove draggable functionality
      widget.draggable = false
    })
  }
  
  makeWidgetDraggable(widget) {
    widget.draggable = true
    
    widget.addEventListener('dragstart', (e) => {
      e.dataTransfer.effectAllowed = 'move'
      e.dataTransfer.setData('text/html', widget.innerHTML)
      widget.classList.add('opacity-50')
    })
    
    widget.addEventListener('dragend', (e) => {
      widget.classList.remove('opacity-50')
    })
    
    widget.addEventListener('dragover', (e) => {
      if (e.preventDefault) {
        e.preventDefault()
      }
      e.dataTransfer.dropEffect = 'move'
      return false
    })
    
    widget.addEventListener('drop', (e) => {
      if (e.stopPropagation) {
        e.stopPropagation()
      }
      return false
    })
  }
  
  showAddModal() {
    if (this.hasModalTarget) {
      this.modalTarget.classList.remove('hidden')
      this.modalTarget.classList.add('flex')
      
      // Focus on first input
      setTimeout(() => {
        const firstInput = this.modalTarget.querySelector('input, select')
        if (firstInput) firstInput.focus()
      }, 100)
    }
  }
  
  hideAddModal() {
    if (this.hasModalTarget) {
      this.modalTarget.classList.add('hidden')
      this.modalTarget.classList.remove('flex')
      
      // Clear form inputs
      document.getElementById('widget-title-input').value = ''
      document.getElementById('widget-type-select').selectedIndex = 0
      document.getElementById('widget-width-input').value = '2'
      document.getElementById('widget-height-input').value = '3'
    }
  }
  
  async addWidget() {
    const widgetType = document.getElementById('widget-type-select').value
    const title = document.getElementById('widget-title-input').value
    const width = document.getElementById('widget-width-input').value
    const height = document.getElementById('widget-height-input').value
    
    if (!title) {
      this.showNotification('Please enter a widget title', 'error')
      return
    }
    
    const dashboardId = this.element.dataset.dashboardId
    
    this.showLoading()
    
    try {
      const response = await fetch(`/dashboards/${dashboardId}/add_widget`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
          'Accept': 'application/json'
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
        this.hideAddModal()
        this.showNotification('Widget added successfully', 'success')
        setTimeout(() => window.location.reload(), 1000)
      } else {
        const error = await response.json()
        this.showNotification(error.errors?.join(', ') || 'Failed to add widget', 'error')
      }
    } catch (error) {
      this.showNotification('An error occurred while adding the widget', 'error')
    } finally {
      this.hideLoading()
    }
  }
  
  async removeWidget(event) {
    const widgetId = event.currentTarget.dataset.widgetId
    const dashboardId = this.element.dataset.dashboardId
    
    if (confirm('Are you sure you want to remove this widget?')) {
      this.showLoading()
      
      try {
        const response = await fetch(`/dashboards/${dashboardId}/remove_widget/${widgetId}`, {
          method: 'DELETE',
          headers: {
            'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
            'Accept': 'application/json'
          }
        })
        
        if (response.ok) {
          const widget = document.querySelector(`[data-widget-id="${widgetId}"]`)
          
          // Animate removal
          widget.style.transition = 'all 0.3s ease'
          widget.style.transform = 'scale(0.9)'
          widget.style.opacity = '0'
          
          setTimeout(() => {
            widget.remove()
            this.showNotification('Widget removed successfully', 'success')
          }, 300)
        } else {
          this.showNotification('Failed to remove widget', 'error')
        }
      } catch (error) {
        this.showNotification('An error occurred while removing the widget', 'error')
      } finally {
        this.hideLoading()
      }
    }
  }
  
  async refreshWidget(event) {
    const button = event.currentTarget
    const widgetId = button.dataset.widgetId
    const dashboardId = this.element.dataset.dashboardId
    
    // Add rotation animation to refresh icon
    const icon = button.querySelector('svg')
    if (icon) {
      icon.classList.add('animate-spin')
    }
    
    try {
      const response = await fetch(`/dashboards/${dashboardId}/refresh_widget/${widgetId}`, {
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
          'Accept': 'application/json'
        }
      })
      
      if (response.ok) {
        const data = await response.json()
        const widget = document.querySelector(`[data-widget-id="${widgetId}"]`)
        const contentDiv = widget.querySelector('.widget-content')
        
        if (contentDiv) {
          contentDiv.dataset.widgetData = JSON.stringify(data.data)
          
          // Add subtle flash animation
          widget.style.transition = 'all 0.2s ease'
          widget.classList.add('ring-2', 'ring-green-500')
          
          setTimeout(() => {
            widget.classList.remove('ring-2', 'ring-green-500')
          }, 500)
        }
      }
    } catch (error) {
      console.error('Error refreshing widget:', error)
    } finally {
      // Stop rotation animation
      if (icon) {
        setTimeout(() => {
          icon.classList.remove('animate-spin')
        }, 500)
      }
    }
  }
  
  async refreshDashboard() {
    const button = event.currentTarget
    const icon = button.querySelector('svg')
    
    // Add rotation animation
    if (icon) {
      icon.classList.add('animate-spin')
    }
    
    this.showNotification('Refreshing dashboard...', 'info')
    
    await this.refreshAllWidgets()
    
    setTimeout(() => {
      if (icon) {
        icon.classList.remove('animate-spin')
      }
      this.showNotification('Dashboard refreshed', 'success')
    }, 1000)
  }
  
  async saveLayout() {
    const widgets = []
    
    this.widgetTargets.forEach(widget => {
      const style = widget.style
      const widgetId = widget.dataset.widgetId
      
      // Get current position from grid styles
      const gridColumn = style.gridColumn || ''
      const colSpan = gridColumn.match(/span (\d+)/)
      const width = colSpan ? parseInt(colSpan[1]) : 2
      
      widgets.push({
        id: widgetId,
        width: width,
        height: 3, // Default height
        col: 0, // Would need to calculate from actual position
        row: 0  // Would need to calculate from actual position
      })
    })
    
    const dashboardId = this.element.dataset.dashboardId
    
    try {
      await fetch(`/dashboards/${dashboardId}/update_layout`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
          'Accept': 'application/json'
        },
        body: JSON.stringify({ widgets })
      })
    } catch (error) {
      console.error('Error saving layout:', error)
    }
  }
  
  setupRefreshInterval() {
    // Auto-refresh widgets every 60 seconds
    this.refreshInterval = setInterval(() => {
      if (!this.editMode) {
        this.refreshAllWidgets()
      }
    }, 60000)
  }
  
  async refreshAllWidgets() {
    const refreshButtons = document.querySelectorAll('[data-action*="refreshWidget"]')
    
    for (const button of refreshButtons) {
      await this.refreshWidget({ currentTarget: button })
      // Small delay between widget refreshes
      await new Promise(resolve => setTimeout(resolve, 100))
    }
  }
  
  changeTimeRange(event) {
    const range = event.currentTarget.dataset.range
    this.currentTimeRange = range
    
    // Update time range display
    const rangeDisplay = document.querySelector('.time-range-display')
    if (rangeDisplay) {
      const rangeLabels = {
        '24h': 'Last 24 Hours',
        '7d': 'Last 7 Days',
        '30d': 'Last 30 Days',
        '90d': 'Last 90 Days',
        '1y': 'Last Year'
      }
      rangeDisplay.textContent = rangeLabels[range] || 'Last 30 Days'
    }
    
    // Refresh all widgets with new time range
    this.refreshAllWidgets()
    this.showNotification(`Time range changed to ${rangeLabels[range]}`, 'info')
  }
  
  showLoading() {
    const loadingOverlay = document.getElementById('dashboard-loading')
    if (loadingOverlay) {
      loadingOverlay.classList.remove('hidden')
    }
  }
  
  hideLoading() {
    const loadingOverlay = document.getElementById('dashboard-loading')
    if (loadingOverlay) {
      loadingOverlay.classList.add('hidden')
    }
  }
  
  showNotification(message, type = 'info') {
    // Create notification element
    const notification = document.createElement('div')
    notification.className = `fixed bottom-4 right-4 px-6 py-3 rounded-lg shadow-lg z-50 transform transition-all duration-300 translate-y-full`
    
    // Set color based on type
    const colors = {
      success: 'bg-teal-500 text-white',
      error: 'bg-red-500 text-white',
      info: 'bg-slate-600 text-white',
      warning: 'bg-amber-500 text-white'
    }
    
    notification.className += ` ${colors[type] || colors.info}`
    notification.textContent = message
    
    // Add to page
    document.body.appendChild(notification)
    
    // Animate in
    setTimeout(() => {
      notification.classList.remove('translate-y-full')
      notification.classList.add('translate-y-0')
    }, 100)
    
    // Remove after 3 seconds
    setTimeout(() => {
      notification.classList.remove('translate-y-0')
      notification.classList.add('translate-y-full')
      
      setTimeout(() => {
        notification.remove()
      }, 300)
    }, 3000)
  }
}