module Api
  module V1
    class DatasetsController < BaseController
      before_action :set_dataset, only: [ :show, :update, :destroy ]
      before_action :check_read_permission, only: [ :index, :show ]
      before_action :check_write_permission, only: [ :create, :update, :destroy ]

      # GET /api/v1/datasets
      def index
        @datasets = @current_organization.datasets
                                         .includes(:data_source_connection)
                                         .order(created_at: :desc)

        @datasets = paginate(@datasets)

        render json: {
          datasets: @datasets.map { |d| serialize_dataset(d) },
          meta: pagination_meta(@datasets)
        }
      end

      # GET /api/v1/datasets/:id
      def show
        render json: { dataset: serialize_dataset(@dataset) }
      end

      # POST /api/v1/datasets
      def create
        @dataset = @current_organization.datasets.build(dataset_params)

        if @dataset.save
          render_success(serialize_dataset(@dataset), status: :created)
        else
          render_error(@dataset.errors.full_messages.join(", "))
        end
      end

      # PATCH/PUT /api/v1/datasets/:id
      def update
        if @dataset.update(dataset_params)
          render_success(serialize_dataset(@dataset))
        else
          render_error(@dataset.errors.full_messages.join(", "))
        end
      end

      # DELETE /api/v1/datasets/:id
      def destroy
        @dataset.destroy
        render_success({ message: "Dataset deleted successfully" })
      end

      private

      def set_dataset
        @dataset = @current_organization.datasets.find(params[:id])
      end

      def dataset_params
        params.require(:dataset).permit(
          :name,
          :description,
          :source_type,
          :connection_config,
          :refresh_frequency,
          :retention_days,
          schema_metadata: {}
        )
      end

      def check_read_permission
        unless @api_token.has_scope?("datasets:read") || @api_token.has_scope?("*")
          render_error("Insufficient permissions", status: :forbidden)
        end
      end

      def check_write_permission
        unless @api_token.has_scope?("datasets:write") || @api_token.has_scope?("*")
          render_error("Insufficient permissions", status: :forbidden)
        end
      end

      def serialize_dataset(dataset)
        {
          id: dataset.id,
          name: dataset.name,
          description: dataset.description,
          source_type: dataset.source_type,
          status: dataset.status,
          row_count: dataset.row_count,
          size_bytes: dataset.size_bytes,
          last_synced_at: dataset.last_synced_at,
          created_at: dataset.created_at,
          updated_at: dataset.updated_at,
          schema_metadata: dataset.schema_metadata,
          data_source_connection: dataset.data_source_connection ? {
            id: dataset.data_source_connection.id,
            name: dataset.data_source_connection.name,
            source_type: dataset.data_source_connection.source_type,
            status: dataset.data_source_connection.status
          } : nil
        }
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
