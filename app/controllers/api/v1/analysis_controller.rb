module Api
  module V1
    class AnalysisController < BaseController
      before_action :check_analysis_permission
      before_action :set_dataset

      # POST /api/v1/analysis
      def create
        @analysis_request = @current_user.analysis_requests.build(
          dataset: @dataset,
          organization: @current_organization,
          natural_language_query: params[:query],
          user_options: params[:options] || {}
        )

        if @analysis_request.save
          # Queue the analysis job
          AnalysisJob.perform_later(@analysis_request)

          render_success({
            analysis_id: @analysis_request.id,
            status: @analysis_request.status,
            message: "Analysis queued successfully",
            estimated_time: estimate_completion_time(@analysis_request)
          }, status: :accepted)
        else
          render_error(@analysis_request.errors.full_messages.join(", "))
        end
      end

      # GET /api/v1/analysis/:id
      def show
        @analysis_request = @current_user.analysis_requests.find(params[:id])

        render json: {
          analysis: serialize_analysis(@analysis_request)
        }
      end

      # GET /api/v1/analysis
      def index
        @analysis_requests = @current_user.analysis_requests
                                          .includes(:dataset)
                                          .order(created_at: :desc)

        @analysis_requests = @analysis_requests.where(dataset_id: params[:dataset_id]) if params[:dataset_id]
        @analysis_requests = @analysis_requests.where(status: params[:status]) if params[:status]
        @analysis_requests = paginate(@analysis_requests)

        render json: {
          analyses: @analysis_requests.map { |a| serialize_analysis(a) },
          meta: pagination_meta(@analysis_requests)
        }
      end

      # POST /api/v1/analysis/:id/cancel
      def cancel
        @analysis_request = @current_user.analysis_requests.find(params[:id])

        if @analysis_request.can_cancel?
          @analysis_request.cancel!
          render_success({ message: "Analysis cancelled successfully" })
        else
          render_error("Cannot cancel analysis in #{@analysis_request.status} status")
        end
      end

      private

      def set_dataset
        return unless params[:dataset_id]
        @dataset = @current_organization.datasets.find(params[:dataset_id])
      end

      def check_analysis_permission
        unless @api_token.has_scope?("analysis:read") || @api_token.has_scope?("*")
          render_error("Insufficient permissions", status: :forbidden)
        end
      end

      def serialize_analysis(analysis)
        {
          id: analysis.id,
          dataset_id: analysis.dataset_id,
          dataset_name: analysis.dataset.name,
          query: analysis.natural_language_query,
          status: analysis.status,
          complexity_score: analysis.complexity_score,
          analyzed_intent: analysis.analyzed_intent,
          final_results: analysis.final_results,
          error_message: analysis.error_message,
          created_at: analysis.created_at,
          updated_at: analysis.updated_at,
          completed_at: analysis.completed_at,
          execution_time: analysis.execution_time_seconds
        }
      end

      def estimate_completion_time(analysis)
        base_time = 30 # seconds
        complexity_factor = (analysis.complexity_score || 5) * 10
        (base_time + complexity_factor).seconds.from_now
      end

      def pagination_meta(collection)
        {
          current_page: collection.current_page,
          total_pages: collection.total_pages,
          total_count: collection.total_count,
          per_page: collection.limit_value
        }
      end
    end
  end
end