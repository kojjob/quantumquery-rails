# frozen_string_literal: true

# Background job for executing code asynchronously in Docker containers
class CodeExecutionJob < ApplicationJob
  queue_as :default

  # Maximum number of retry attempts
  retry_on StandardError, wait: :exponentially_longer, attempts: 2

  discard_on ActiveJob::DeserializationError

  def perform(execution_step)
    Rails.logger.info "Starting code execution for step #{execution_step.id}"

    # Ensure step is in correct state
    unless execution_step.status_executing?
      Rails.logger.warn "Step #{execution_step.id} not in executing state, skipping"
      return
    end

    begin
      # Prepare execution options
      options = prepare_execution_options(execution_step)

      # Build appropriate executor
      executor = CodeExecution::ExecutorFactory.build(
        execution_step.language,
        execution_step.generated_code,
        options
      )

      # Execute code
      result = executor.execute

      # Process results
      process_execution_result(execution_step, result)

    rescue => e
      handle_execution_error(execution_step, e)
    end
  end

  private

  def prepare_execution_options(execution_step)
    analysis_request = execution_step.analysis_request
    dataset = analysis_request.dataset

    options = {
      timeout: calculate_timeout(execution_step),
      memory_limit: calculate_memory_limit(execution_step),
      cpu_shares: 512 # 50% of one CPU
    }

    # Add dataset for SQL execution
    if execution_step.language == "sql"
      options[:dataset] = dataset
    end

    # Prepare dataset file for Python/R execution
    if %w[python r].include?(execution_step.language) && dataset
      options[:dataset_path] = prepare_dataset_file(dataset)
    end

    # Create output directory for generated files
    options[:output_dir] = Rails.root.join("tmp", "executions", execution_step.id.to_s)
    FileUtils.mkdir_p(options[:output_dir])

    options
  end

  def calculate_timeout(execution_step)
    # Base timeout on complexity
    base_timeout = 30 # seconds
    complexity_multiplier = execution_step.analysis_request.complexity_score || 5.0
    
    [base_timeout * (complexity_multiplier / 5.0), 120].min.to_i
  end

  def calculate_memory_limit(execution_step)
    # Base memory limit
    base_memory = 256 * 1024 * 1024 # 256MB
    
    # Increase for complex analyses
    complexity = execution_step.analysis_request.complexity_score || 5.0
    (base_memory * (complexity / 5.0)).to_i.clamp(256 * 1024 * 1024, 1024 * 1024 * 1024)
  end

  def prepare_dataset_file(dataset)
    # For file-based datasets (CSV, Excel), use the attached file
    if dataset.data_file.attached?
      # Download to temp location if needed
      temp_path = Rails.root.join("tmp", "datasets", "#{dataset.id}_#{dataset.data_file.filename}")
      FileUtils.mkdir_p(File.dirname(temp_path))
      
      unless File.exist?(temp_path)
        File.open(temp_path, "wb") do |file|
          dataset.data_file.download { |chunk| file.write(chunk) }
        end
      end
      
      return temp_path.to_s
    end

    # For database datasets, export to CSV
    if %w[postgresql mysql mongodb].include?(dataset.data_source_type)
      export_dataset_to_csv(dataset)
    end

    nil
  end

  def export_dataset_to_csv(dataset)
    # Export first 10,000 rows to CSV for analysis
    # This is a simplified version - in production, you might want to be smarter about this
    
    temp_path = Rails.root.join("tmp", "datasets", "#{dataset.id}_export.csv")
    FileUtils.mkdir_p(File.dirname(temp_path))
    
    # Cache for 1 hour
    return temp_path.to_s if File.exist?(temp_path) && File.mtime(temp_path) > 1.hour.ago

    # TODO: Implement actual export logic based on dataset type
    # For now, return nil to skip dataset mounting
    nil
  end

  def process_execution_result(execution_step, result)
    if result.success?
      Rails.logger.info "Code execution successful for step #{execution_step.id}"
      
      # Store results
      execution_step.update!(
        status: :completed,
        result_data: parse_output(result.output),
        raw_output: result.output,
        execution_time_ms: (result.duration_seconds * 1000).to_i,
        metadata: execution_step.metadata.merge(
          "execution" => {
            "exit_code" => result.exit_code,
            "duration_seconds" => result.duration_seconds,
            "metadata" => result.metadata
          }
        )
      )

      # Handle generated files (visualizations, reports, etc.)
      handle_generated_files(execution_step, result)

    else
      Rails.logger.error "Code execution failed for step #{execution_step.id}: #{result.error}"
      
      execution_step.update!(
        status: :failed,
        error_message: result.error,
        raw_output: result.output,
        execution_time_ms: (result.duration_seconds * 1000).to_i,
        metadata: execution_step.metadata.merge(
          "execution" => {
            "exit_code" => result.exit_code,
            "duration_seconds" => result.duration_seconds,
            "error" => result.error
          }
        )
      )
    end
  end

  def handle_execution_error(execution_step, error)
    Rails.logger.error "Code execution error for step #{execution_step.id}: #{error.message}"
    Rails.logger.error error.backtrace.join("\n")

    execution_step.update!(
      status: :failed,
      error_message: "Execution error: #{error.message}",
      metadata: execution_step.metadata.merge(
        "execution_error" => {
          "class" => error.class.name,
          "message" => error.message,
          "backtrace" => error.backtrace.first(5)
        }
      )
    )
  end

  def parse_output(output)
    # Try to parse as JSON
    JSON.parse(output)
  rescue JSON::ParserError
    # Return as plain text
    { "output" => output }
  end

  def handle_generated_files(execution_step, result)
    generated_files = result.metadata[:generated_files]
    return unless generated_files&.any?

    # Attach generated files to execution step
    generated_files.each do |file_info|
      next unless File.exist?(file_info[:path])

      # Determine if it's a visualization based on file type
      is_visualization = %w[.png .jpg .jpeg .svg .pdf].include?(File.extname(file_info[:filename]))

      if is_visualization
        # TODO: Create visualization record and attach file
        # visualization = execution_step.visualizations.create!(
        #   title: file_info[:filename],
        #   visualization_type: determine_viz_type(file_info[:filename])
        # )
        # visualization.file.attach(
        #   io: File.open(file_info[:path]),
        #   filename: file_info[:filename]
        # )
      else
        # Attach as general output file
        # execution_step.output_files.attach(
        #   io: File.open(file_info[:path]),
        #   filename: file_info[:filename]
        # )
      end
    end
  end
end
