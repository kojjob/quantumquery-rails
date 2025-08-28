class QueryCachesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_organization
  before_action :set_dataset, only: [:index, :dataset_stats]
  before_action :set_query_cache, only: [:show, :refresh, :destroy]
  
  def index
    @query_caches = if @dataset
                      @dataset.query_caches.active.includes(:dataset).order(accessed_at: :desc)
                    else
                      @organization.query_caches.active.includes(:dataset).order(accessed_at: :desc)
                    end
    
    @query_caches = @query_caches.page(params[:page])
    
    respond_to do |format|
      format.html
      format.json { render json: @query_caches }
    end
  end
  
  def show
    respond_to do |format|
      format.html
      format.json { 
        render json: {
          cache: @query_cache,
          results: @query_cache.results,
          metadata: @query_cache.metadata,
          hit_rate: @query_cache.hit_rate
        }
      }
    end
  end
  
  def statistics
    cache_service = QueryCacheService.new(@organization, nil)
    @stats = cache_service.cache_statistics
    
    # Additional statistics
    @stats[:cache_by_dataset] = @organization.datasets.map do |dataset|
      {
        name: dataset.name,
        entries: dataset.query_caches.count,
        active: dataset.query_caches.active.count,
        size_mb: (dataset.query_caches.sum(:cache_size_bytes) / 1.megabyte.to_f).round(2)
      }
    end
    
    @stats[:recent_activity] = @organization.query_caches
                                            .order(accessed_at: :desc)
                                            .limit(10)
                                            .map do |cache|
      {
        query: cache.query_text.truncate(100),
        dataset: cache.dataset.name,
        accessed_at: cache.accessed_at,
        access_count: cache.access_count
      }
    end
    
    respond_to do |format|
      format.html
      format.json { render json: @stats }
    end
  end
  
  def dataset_stats
    cache_service = QueryCacheService.new(@organization, @dataset)
    @stats = cache_service.cache_statistics
    
    respond_to do |format|
      format.html
      format.json { render json: @stats }
    end
  end
  
  def refresh
    RefreshCacheJob.perform_later(@query_cache.id)
    
    respond_to do |format|
      format.html { 
        redirect_to query_caches_path, notice: 'Cache refresh queued successfully.'
      }
      format.json { 
        render json: { status: 'queued', message: 'Cache refresh has been queued' }
      }
    end
  end
  
  def destroy
    @query_cache.destroy
    
    respond_to do |format|
      format.html { 
        redirect_to query_caches_path, notice: 'Cache entry deleted successfully.'
      }
      format.json { head :no_content }
    end
  end
  
  def clear_all
    if params[:dataset_id]
      dataset = @organization.datasets.find(params[:dataset_id])
      cache_service = QueryCacheService.new(@organization, dataset)
      cache_service.invalidate_dataset_cache!
      message = "All cache entries for #{dataset.name} have been invalidated."
    else
      @organization.query_caches.update_all(expires_at: Time.current)
      message = "All cache entries have been invalidated."
    end
    
    respond_to do |format|
      format.html { 
        redirect_to query_caches_path, notice: message
      }
      format.json { 
        render json: { status: 'success', message: message }
      }
    end
  end
  
  def clear_expired
    count = QueryCache.cleanup_expired!
    
    respond_to do |format|
      format.html { 
        redirect_to query_caches_path, notice: "#{count} expired cache entries have been removed."
      }
      format.json { 
        render json: { status: 'success', removed_count: count }
      }
    end
  end
  
  private
  
  def set_organization
    @organization = current_user.organization
  end
  
  def set_dataset
    @dataset = @organization.datasets.find(params[:dataset_id]) if params[:dataset_id]
  end
  
  def set_query_cache
    @query_cache = @organization.query_caches.find(params[:id])
  end
end