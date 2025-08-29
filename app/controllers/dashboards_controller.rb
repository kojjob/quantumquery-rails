class DashboardsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_dashboard, only: [:show, :edit, :update, :destroy, :duplicate]
  
  def index
    @dashboards = current_user.dashboards.order(:position)
    
    # Create default dashboards if user has none
    if @dashboards.empty?
      create_default_dashboards
      @dashboards = current_user.dashboards.order(:position)
    end
  end
  
  def show
    @widgets = @dashboard.dashboard_widgets.ordered
    respond_to do |format|
      format.html
      format.json { render json: dashboard_json }
    end
  end
  
  def new
    @dashboard = current_user.dashboards.build
  end
  
  def create
    @dashboard = current_user.dashboards.build(dashboard_params)
    
    if @dashboard.save
      redirect_to @dashboard, notice: "Dashboard created successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end
  
  def edit
  end
  
  def update
    if @dashboard.update(dashboard_params)
      redirect_to @dashboard, notice: "Dashboard updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end
  
  def destroy
    @dashboard.destroy
    redirect_to dashboards_path, notice: "Dashboard deleted successfully."
  end
  
  def duplicate
    new_dashboard = @dashboard.duplicate_for_user(current_user)
    if new_dashboard.persisted?
      redirect_to new_dashboard, notice: "Dashboard duplicated successfully."
    else
      redirect_to dashboards_path, alert: "Failed to duplicate dashboard."
    end
  end
  
  # Widget management actions
  def add_widget
    @dashboard = current_user.dashboards.find(params[:id])
    @widget = @dashboard.dashboard_widgets.build(widget_params)
    
    if @widget.save
      render json: { widget: widget_json(@widget) }, status: :created
    else
      render json: { errors: @widget.errors.full_messages }, status: :unprocessable_entity
    end
  end
  
  def update_widget
    @dashboard = current_user.dashboards.find(params[:id])
    @widget = @dashboard.dashboard_widgets.find(params[:widget_id])
    
    if @widget.update(widget_params)
      render json: { widget: widget_json(@widget) }
    else
      render json: { errors: @widget.errors.full_messages }, status: :unprocessable_entity
    end
  end
  
  def remove_widget
    @dashboard = current_user.dashboards.find(params[:id])
    @widget = @dashboard.dashboard_widgets.find(params[:widget_id])
    @widget.destroy
    
    head :no_content
  end
  
  def refresh_widget
    @dashboard = current_user.dashboards.find(params[:id])
    @widget = @dashboard.dashboard_widgets.find(params[:widget_id])
    
    render json: { data: @widget.data }
  end
  
  def update_layout
    @dashboard = current_user.dashboards.find(params[:id])
    
    params[:widgets].each do |widget_data|
      widget = @dashboard.dashboard_widgets.find(widget_data[:id])
      widget.update(
        row: widget_data[:row],
        col: widget_data[:col],
        width: widget_data[:width],
        height: widget_data[:height]
      )
    end
    
    head :ok
  end
  
  private
  
  def set_dashboard
    @dashboard = current_user.dashboards.find(params[:id])
  end
  
  def dashboard_params
    params.require(:dashboard).permit(:name, :description, :layout, :is_default, config: {})
  end
  
  def widget_params
    params.require(:widget).permit(:widget_type, :title, :row, :col, :width, :height, config: {})
  end
  
  def create_default_dashboards
    # Create Overview Dashboard
    overview = current_user.dashboards.create!(
      name: "Overview Dashboard",
      description: "General overview of your data analysis activity",
      layout: "grid",
      is_default: true,
      position: 1,
      config: Dashboard::DEFAULT_CONFIG
    )
    
    # Create Analytics Dashboard
    analytics = current_user.dashboards.create!(
      name: "Analytics Dashboard",
      description: "Detailed analytics and insights",
      layout: "grid",
      is_default: true,
      position: 2,
      config: Dashboard::DEFAULT_CONFIG
    )
  end
  
  def dashboard_json
    {
      id: @dashboard.id,
      name: @dashboard.name,
      description: @dashboard.description,
      layout: @dashboard.layout,
      config: @dashboard.config,
      widgets: @dashboard.dashboard_widgets.ordered.map { |w| widget_json(w) }
    }
  end
  
  def widget_json(widget)
    {
      id: widget.id,
      type: widget.widget_type,
      title: widget.title,
      position: {
        row: widget.row,
        col: widget.col,
        width: widget.width,
        height: widget.height
      },
      config: widget.config,
      data: widget.data
    }
  end
end