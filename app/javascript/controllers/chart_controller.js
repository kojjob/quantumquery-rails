import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"

// Register all Chart.js components
Chart.register(...registerables)

// Connects to data-controller="chart"
export default class extends Controller {
  static targets = ["canvas"]
  static values = { 
    type: String,
    data: Object,
    options: Object,
    chartId: String
  }

  connect() {
    this.initializeChart()
  }

  disconnect() {
    if (this.chart) {
      this.chart.destroy()
    }
  }

  initializeChart() {
    const ctx = this.canvasTarget.getContext('2d')
    
    // Destroy existing chart if it exists
    if (this.chart) {
      this.chart.destroy()
    }

    // Create new chart
    this.chart = new Chart(ctx, {
      type: this.typeValue || 'bar',
      data: this.dataValue || this.defaultData(),
      options: this.mergeOptions()
    })

    // Store chart instance for external access
    if (this.chartIdValue) {
      window.quantumQueryCharts = window.quantumQueryCharts || {}
      window.quantumQueryCharts[this.chartIdValue] = this.chart
    }
  }

  updateChart(event) {
    const { data, options } = event.detail
    
    if (data) {
      this.chart.data = data
    }
    
    if (options) {
      this.chart.options = this.mergeOptions(options)
    }
    
    this.chart.update()
  }

  exportChart() {
    const url = this.canvasTarget.toDataURL('image/png')
    const link = document.createElement('a')
    link.download = `chart-${Date.now()}.png`
    link.href = url
    link.click()
  }

  mergeOptions(customOptions = {}) {
    const defaultOptions = {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: {
          position: 'top',
        },
        tooltip: {
          mode: 'index',
          intersect: false,
          backgroundColor: 'rgba(0, 0, 0, 0.8)',
          titleColor: '#fff',
          bodyColor: '#fff',
          borderColor: 'rgb(102, 126, 234)',
          borderWidth: 1
        }
      },
      interaction: {
        mode: 'nearest',
        axis: 'x',
        intersect: false
      }
    }

    return {
      ...defaultOptions,
      ...this.optionsValue,
      ...customOptions
    }
  }

  defaultData() {
    return {
      labels: ['January', 'February', 'March', 'April', 'May', 'June'],
      datasets: [{
        label: 'Sample Data',
        data: [12, 19, 3, 5, 2, 3],
        backgroundColor: 'rgba(102, 126, 234, 0.6)',
        borderColor: 'rgb(102, 126, 234)',
        borderWidth: 1
      }]
    }
  }

  // Action to refresh chart with new data from server
  async refreshData() {
    try {
      const response = await fetch(this.data.get('refresh-url'))
      const data = await response.json()
      
      this.chart.data = data.chartData
      this.chart.options = this.mergeOptions(data.chartOptions)
      this.chart.update()
    } catch (error) {
      console.error('Failed to refresh chart data:', error)
    }
  }

  // Handle chart type changes
  changeType(event) {
    const newType = event.target.value
    
    // Some chart types need special handling
    const currentData = this.chart.data
    
    // Destroy and recreate chart with new type
    this.chart.destroy()
    this.chart = new Chart(this.canvasTarget.getContext('2d'), {
      type: newType,
      data: currentData,
      options: this.mergeOptions()
    })
  }
}