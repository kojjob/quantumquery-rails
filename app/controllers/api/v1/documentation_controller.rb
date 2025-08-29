module Api
  module V1
    class DocumentationController < BaseController
      skip_before_action :authenticate_api_token!

      # GET /api/v1/documentation
      def index
        render json: openapi_spec
      end

      private

      def openapi_spec
        {
          openapi: "3.0.0",
          info: {
            title: "QuantumQuery API",
            description: "Natural language data analysis platform API",
            version: "1.0.0",
            contact: {
              name: "API Support",
              email: "api@quantumquery.io"
            }
          },
          servers: [
            {
              url: "#{request.protocol}#{request.host_with_port}/api/v1",
              description: "Current server"
            }
          ],
          security: [
            {
              bearerAuth: []
            }
          ],
          components: {
            securitySchemes: {
              bearerAuth: {
                type: "http",
                scheme: "bearer",
                description: "API token authentication"
              }
            },
            schemas: {
              Dataset: dataset_schema,
              Analysis: analysis_schema,
              Error: error_schema,
              PaginationMeta: pagination_meta_schema
            }
          },
          paths: api_paths
        }
      end

      def api_paths
        {
          "/datasets": {
            get: {
              summary: "List all datasets",
              tags: [ "Datasets" ],
              parameters: [
                { name: "page", in: "query", schema: { type: "integer" }, description: "Page number" },
                { name: "per_page", in: "query", schema: { type: "integer" }, description: "Items per page" }
              ],
              responses: {
                "200": {
                  description: "Successful response",
                  content: {
                    "application/json": {
                      schema: {
                        type: "object",
                        properties: {
                          datasets: { type: "array", items: { "$ref": "#/components/schemas/Dataset" } },
                          meta: { "$ref": "#/components/schemas/PaginationMeta" }
                        }
                      }
                    }
                  }
                }
              }
            },
            post: {
              summary: "Create a new dataset",
              tags: [ "Datasets" ],
              requestBody: {
                required: true,
                content: {
                  "application/json": {
                    schema: {
                      type: "object",
                      required: [ "dataset" ],
                      properties: {
                        dataset: {
                          type: "object",
                          required: [ "name", "source_type" ],
                          properties: {
                            name: { type: "string" },
                            description: { type: "string" },
                            source_type: { type: "string", enum: [ "csv", "json", "api", "database" ] },
                            connection_config: { type: "object" }
                          }
                        }
                      }
                    }
                  }
                }
              },
              responses: {
                "201": { description: "Dataset created" },
                "422": { description: "Validation errors" }
              }
            }
          },
          "/datasets/{id}": {
            get: {
              summary: "Get a specific dataset",
              tags: [ "Datasets" ],
              parameters: [
                { name: "id", in: "path", required: true, schema: { type: "integer" } }
              ],
              responses: {
                "200": {
                  description: "Successful response",
                  content: {
                    "application/json": {
                      schema: { "$ref": "#/components/schemas/Dataset" }
                    }
                  }
                },
                "404": { description: "Dataset not found" }
              }
            },
            put: {
              summary: "Update a dataset",
              tags: [ "Datasets" ],
              parameters: [
                { name: "id", in: "path", required: true, schema: { type: "integer" } }
              ],
              requestBody: {
                required: true,
                content: {
                  "application/json": {
                    schema: {
                      type: "object",
                      properties: {
                        dataset: {
                          type: "object",
                          properties: {
                            name: { type: "string" },
                            description: { type: "string" }
                          }
                        }
                      }
                    }
                  }
                }
              },
              responses: {
                "200": { description: "Dataset updated" },
                "404": { description: "Dataset not found" }
              }
            },
            delete: {
              summary: "Delete a dataset",
              tags: [ "Datasets" ],
              parameters: [
                { name: "id", in: "path", required: true, schema: { type: "integer" } }
              ],
              responses: {
                "200": { description: "Dataset deleted" },
                "404": { description: "Dataset not found" }
              }
            }
          },
          "/analysis": {
            get: {
              summary: "List analysis requests",
              tags: [ "Analysis" ],
              parameters: [
                { name: "dataset_id", in: "query", schema: { type: "integer" } },
                { name: "status", in: "query", schema: { type: "string" } },
                { name: "page", in: "query", schema: { type: "integer" } },
                { name: "per_page", in: "query", schema: { type: "integer" } }
              ],
              responses: {
                "200": {
                  description: "Successful response",
                  content: {
                    "application/json": {
                      schema: {
                        type: "object",
                        properties: {
                          analyses: { type: "array", items: { "$ref": "#/components/schemas/Analysis" } },
                          meta: { "$ref": "#/components/schemas/PaginationMeta" }
                        }
                      }
                    }
                  }
                }
              }
            },
            post: {
              summary: "Create a new analysis request",
              tags: [ "Analysis" ],
              requestBody: {
                required: true,
                content: {
                  "application/json": {
                    schema: {
                      type: "object",
                      required: [ "query", "dataset_id" ],
                      properties: {
                        query: { type: "string", description: "Natural language query" },
                        dataset_id: { type: "integer", description: "ID of the dataset to analyze" },
                        options: {
                          type: "object",
                          properties: {
                            skip_cache: { type: "boolean" },
                            model: { type: "string" }
                          }
                        }
                      }
                    }
                  }
                }
              },
              responses: {
                "202": {
                  description: "Analysis queued",
                  content: {
                    "application/json": {
                      schema: {
                        type: "object",
                        properties: {
                          analysis_id: { type: "integer" },
                          status: { type: "string" },
                          message: { type: "string" },
                          estimated_time: { type: "string", format: "date-time" }
                        }
                      }
                    }
                  }
                }
              }
            }
          },
          "/analysis/{id}": {
            get: {
              summary: "Get analysis results",
              tags: [ "Analysis" ],
              parameters: [
                { name: "id", in: "path", required: true, schema: { type: "integer" } }
              ],
              responses: {
                "200": {
                  description: "Successful response",
                  content: {
                    "application/json": {
                      schema: { "$ref": "#/components/schemas/Analysis" }
                    }
                  }
                },
                "404": { description: "Analysis not found" }
              }
            }
          },
          "/analysis/{id}/cancel": {
            post: {
              summary: "Cancel an analysis request",
              tags: [ "Analysis" ],
              parameters: [
                { name: "id", in: "path", required: true, schema: { type: "integer" } }
              ],
              responses: {
                "200": { description: "Analysis cancelled" },
                "422": { description: "Cannot cancel analysis" }
              }
            }
          }
        }
      end

      def dataset_schema
        {
          type: "object",
          properties: {
            id: { type: "integer" },
            name: { type: "string" },
            description: { type: "string" },
            source_type: { type: "string" },
            status: { type: "string" },
            row_count: { type: "integer" },
            size_bytes: { type: "integer" },
            last_synced_at: { type: "string", format: "date-time" },
            created_at: { type: "string", format: "date-time" },
            updated_at: { type: "string", format: "date-time" }
          }
        }
      end

      def analysis_schema
        {
          type: "object",
          properties: {
            id: { type: "integer" },
            dataset_id: { type: "integer" },
            dataset_name: { type: "string" },
            query: { type: "string" },
            status: { type: "string" },
            complexity_score: { type: "number" },
            final_results: { type: "object" },
            error_message: { type: "string" },
            created_at: { type: "string", format: "date-time" },
            completed_at: { type: "string", format: "date-time" },
            execution_time: { type: "number" }
          }
        }
      end

      def error_schema
        {
          type: "object",
          properties: {
            error: { type: "string" },
            message: { type: "string" },
            errors: { type: "array", items: { type: "string" } }
          }
        }
      end

      def pagination_meta_schema
        {
          type: "object",
          properties: {
            current_page: { type: "integer" },
            total_pages: { type: "integer" },
            total_count: { type: "integer" },
            per_page: { type: "integer" }
          }
        }
      end
    end
  end
end
