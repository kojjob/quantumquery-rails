class Dashboard < ApplicationRecord
  belongs_to :user
  has_many :dashboard_widgets, dependent: :destroy

  # Validations
  validates :name, presence: true
  validates :layout, inclusion: { in: %w[grid flex columns] }, allow_blank: true

  # Scopes
  scope :default_dashboards, -> { where(is_default: true) }
  scope :user_dashboards, -> { where(is_default: false) }

  # Callbacks
  before_create :set_position
  after_create :create_default_widgets, if: :is_default?

  # Default configuration
  DEFAULT_CONFIG = {
    grid_cols: 12,
    row_height: 80,
    margin: [ 10, 10 ],
    container_padding: [ 10, 10 ],
    auto_size: true,
    draggable: true,
    resizable: true
  }.freeze

  WIDGET_TYPES = {
    metric_card: "Metric Card",
    line_chart: "Line Chart",
    bar_chart: "Bar Chart",
    pie_chart: "Pie Chart",
    data_table: "Data Table",
    recent_queries: "Recent Queries",
    quick_insights: "Quick Insights",
    dataset_overview: "Dataset Overview"
  }.freeze

  def duplicate_for_user(new_user)
    new_dashboard = dup
    new_dashboard.user = new_user
    new_dashboard.is_default = false
    new_dashboard.name = "#{name} (Copy)"

    if new_dashboard.save
      dashboard_widgets.each do |widget|
        new_widget = widget.dup
        new_widget.dashboard = new_dashboard
        new_widget.save
      end
    end

    new_dashboard
  end

  private

  def set_position
    self.position ||= user.dashboards.maximum(:position).to_i + 1
  end

  def create_default_widgets
    # Create default widgets for new dashboard
    case name
    when "Overview Dashboard"
      create_overview_widgets
    when "Analytics Dashboard"
      create_analytics_widgets
    end
  end

  def create_overview_widgets
    dashboard_widgets.create!(
      widget_type: "metric_card",
      title: "Total Queries",
      position: 1,
      row: 0,
      col: 0,
      width: 3,
      height: 2,
      config: {
        metric: "total_queries",
        period: "month",
        comparison: "previous_month"
      }
    )

    dashboard_widgets.create!(
      widget_type: "metric_card",
      title: "Active Datasets",
      position: 2,
      row: 0,
      col: 3,
      width: 3,
      height: 2,
      config: {
        metric: "active_datasets"
      }
    )

    dashboard_widgets.create!(
      widget_type: "line_chart",
      title: "Query Trends",
      position: 3,
      row: 2,
      col: 0,
      width: 6,
      height: 4,
      config: {
        metric: "queries_over_time",
        period: "30days",
        group_by: "day"
      }
    )

    dashboard_widgets.create!(
      widget_type: "recent_queries",
      title: "Recent Queries",
      position: 4,
      row: 2,
      col: 6,
      width: 6,
      height: 4,
      config: {
        limit: 5
      }
    )
  end

  def create_analytics_widgets
    dashboard_widgets.create!(
      widget_type: "bar_chart",
      title: "Queries by Dataset",
      position: 1,
      row: 0,
      col: 0,
      width: 6,
      height: 4,
      config: {
        metric: "queries_by_dataset",
        period: "7days"
      }
    )

    dashboard_widgets.create!(
      widget_type: "pie_chart",
      title: "Query Complexity Distribution",
      position: 2,
      row: 0,
      col: 6,
      width: 6,
      height: 4,
      config: {
        metric: "complexity_distribution"
      }
    )

    dashboard_widgets.create!(
      widget_type: "data_table",
      title: "Top Queries",
      position: 3,
      row: 4,
      col: 0,
      width: 12,
      height: 5,
      config: {
        columns: [ "query", "dataset", "execution_time", "created_at" ],
        sort_by: "execution_time",
        limit: 10
      }
    )
  end
end
