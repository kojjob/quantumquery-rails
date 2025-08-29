class DashboardWidget < ApplicationRecord
  belongs_to :dashboard

  # Validations
  validates :widget_type, presence: true
  validates :title, presence: true
  validates :position, :row, :col, :width, :height, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # Scopes
  scope :ordered, -> { order(:position) }

  # Callbacks
  before_validation :set_defaults

  def data
    case widget_type
    when "metric_card"
      fetch_metric_data
    when "line_chart"
      fetch_line_chart_data
    when "bar_chart"
      fetch_bar_chart_data
    when "pie_chart"
      fetch_pie_chart_data
    when "data_table"
      fetch_table_data
    when "recent_queries"
      fetch_recent_queries
    when "quick_insights"
      fetch_quick_insights
    when "dataset_overview"
      fetch_dataset_overview
    else
      {}
    end
  end

  private

  def set_defaults
    self.position ||= 0
    self.row ||= 0
    self.col ||= 0
    self.width ||= 3
    self.height ||= 2
    self.config ||= {}
  end

  def fetch_metric_data
    user = dashboard.user

    case config["metric"]
    when "total_queries"
      period = config["period"] || "month"
      count = user.analysis_requests.where("created_at > ?", period_start(period)).count
      comparison = if config["comparison"]
        previous_count = user.analysis_requests.where(
          created_at: previous_period_range(period)
        ).count
        calculate_percentage_change(count, previous_count)
      end

      {
        value: count,
        label: "Total Queries",
        change: comparison,
        trend: comparison && comparison > 0 ? "up" : "down"
      }

    when "active_datasets"
      count = user.organization&.datasets&.active&.count || 0
      {
        value: count,
        label: "Active Datasets",
        icon: "database"
      }

    else
      { value: 0, label: "No Data" }
    end
  end

  def fetch_line_chart_data
    user = dashboard.user
    period = config["period"] || "30days"
    group_by = config["group_by"] || "day"

    data = user.analysis_requests
      .where("created_at > ?", period_start(period))
      .group_by_period(group_by.to_sym, :created_at)
      .count

    {
      labels: data.keys.map { |k| k.strftime("%b %d") },
      datasets: [ {
        label: "Queries",
        data: data.values,
        borderColor: "rgb(147, 51, 234)",
        backgroundColor: "rgba(147, 51, 234, 0.1)"
      } ]
    }
  end

  def fetch_bar_chart_data
    user = dashboard.user
    period = config["period"] || "7days"

    data = user.analysis_requests
      .joins(:dataset)
      .where("analysis_requests.created_at > ?", period_start(period))
      .group("datasets.name")
      .count
      .sort_by { |_, v| -v }
      .first(5)

    {
      labels: data.map(&:first),
      datasets: [ {
        label: "Queries",
        data: data.map(&:last),
        backgroundColor: [
          "rgba(147, 51, 234, 0.8)",
          "rgba(79, 70, 229, 0.8)",
          "rgba(99, 102, 241, 0.8)",
          "rgba(139, 92, 246, 0.8)",
          "rgba(168, 85, 247, 0.8)"
        ]
      } ]
    }
  end

  def fetch_pie_chart_data
    user = dashboard.user

    data = user.analysis_requests
      .group(:complexity_score)
      .count

    complexity_ranges = {
      "Simple (0-3)" => data.select { |k, _| k && k < 3 }.values.sum,
      "Moderate (3-7)" => data.select { |k, _| k && k >= 3 && k < 7 }.values.sum,
      "Complex (7-10)" => data.select { |k, _| k && k >= 7 }.values.sum
    }

    {
      labels: complexity_ranges.keys,
      datasets: [ {
        data: complexity_ranges.values,
        backgroundColor: [
          "rgba(34, 197, 94, 0.8)",
          "rgba(251, 191, 36, 0.8)",
          "rgba(239, 68, 68, 0.8)"
        ]
      } ]
    }
  end

  def fetch_table_data
    user = dashboard.user
    columns = config["columns"] || [ "query", "dataset", "created_at" ]
    sort_by = config["sort_by"] || "created_at"
    limit = config["limit"] || 10

    queries = user.analysis_requests.includes(:dataset)
    
    # Handle special ordering cases
    if sort_by == "execution_time"
      # Order by execution_time column with fallback to metadata
      queries = queries.order(
        Arel.sql("COALESCE(execution_time, (metadata->>'execution_time')::numeric) DESC NULLS LAST")
      )
    else
      # Standard column ordering
      queries = queries.order(sort_by => :desc)
    end
    
    queries = queries.limit(limit)

    {
      columns: columns.map(&:humanize),
      rows: queries.map do |query|
        columns.map do |col|
          case col
          when "query"
            query.natural_language_query&.truncate(50)
          when "dataset"
            query.dataset.name
          when "execution_time"
            # Use column value with fallback to metadata
            time = query.execution_time || query.metadata&.dig("execution_time") || 0
            "#{time.to_f.round(2)}s"
          when "created_at"
            query.created_at.strftime("%b %d, %I:%M %p")
          else
            query.send(col) rescue nil
          end
        end
      end
    }
  end

  def fetch_recent_queries
    user = dashboard.user
    limit = config["limit"] || 5

    queries = user.analysis_requests
      .includes(:dataset)
      .order(created_at: :desc)
      .limit(limit)

    {
      queries: queries.map do |query|
        {
          id: query.id,
          query: query.natural_language_query,
          dataset: query.dataset.name,
          status: query.status,
          time_ago: time_ago_in_words(query.created_at)
        }
      end
    }
  end

  def fetch_quick_insights
    user = dashboard.user

    {
      insights: [
        {
          type: "trend",
          message: "Query volume increased by 23% this week",
          icon: "trending_up"
        },
        {
          type: "suggestion",
          message: "Try using natural language for complex queries",
          icon: "lightbulb"
        },
        {
          type: "achievement",
          message: "You've analyzed 1,000+ data points",
          icon: "trophy"
        }
      ]
    }
  end

  def fetch_dataset_overview
    user = dashboard.user
    datasets = user.organization&.datasets&.active || []

    {
      datasets: datasets.map do |dataset|
        {
          id: dataset.id,
          name: dataset.name,
          type: dataset.data_source_type,
          status: dataset.status,
          last_synced: dataset.metadata&.dig("last_synced_at"),
          row_count: dataset.metadata&.dig("row_count") || 0
        }
      end
    }
  end

  def period_start(period)
    case period
    when "day" then 1.day.ago
    when "week" then 1.week.ago
    when "month" then 1.month.ago
    when "year" then 1.year.ago
    when /(\d+)days/ then $1.to_i.days.ago
    else 1.month.ago
    end
  end

  def previous_period_range(period)
    case period
    when "day" then 2.days.ago..1.day.ago
    when "week" then 2.weeks.ago..1.week.ago
    when "month" then 2.months.ago..1.month.ago
    when "year" then 2.years.ago..1.year.ago
    else 2.months.ago..1.month.ago
    end
  end

  def calculate_percentage_change(current, previous)
    return 0 if previous.zero?
    ((current - previous).to_f / previous * 100).round(1)
  end

  def time_ago_in_words(time)
    seconds = Time.current - time
    case seconds
    when 0..59 then "just now"
    when 60..3599 then "#{(seconds / 60).round} minutes ago"
    when 3600..86399 then "#{(seconds / 3600).round} hours ago"
    else "#{(seconds / 86400).round} days ago"
    end
  end
end
