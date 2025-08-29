// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// Charting libraries
import "chartkick"
import "chart.js"

// Initialize Chartkick with Chart.js
import Chartkick from "chartkick"
import Chart from "chart.js"
Chartkick.use(Chart)
