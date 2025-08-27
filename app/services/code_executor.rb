# Secure code execution service using Docker containers
class CodeExecutor
  include ActiveModel::Model
  
  EXECUTION_TIMEOUT = 30.seconds
  MAX_OUTPUT_SIZE = 10.megabytes
  ALLOWED_LANGUAGES = %w[python r sql].freeze
  
  attr_accessor :code, :language, :execution_step, :datasets
  
  validates :code, :language, :execution_step, presence: true
  validates :language, inclusion: { in: ALLOWED_LANGUAGES }
  
  def execute
    return false unless valid?
    
    execution_step.update!(status: 'executing', started_at: Time.current)
    
    case language
    when 'python'
      execute_python
    when 'r'
      execute_r
    when 'sql'
      execute_sql
    else
      raise "Unsupported language: #{language}"
    end
    
    execution_step.update!(
      status: 'completed',
      completed_at: Time.current,
      execution_time: execution_step.completed_at - execution_step.started_at
    )
    
    true
  rescue => e
    handle_execution_error(e)
    false
  end
  
  private
  
  def execute_python
    container_id = create_container
    
    # Write code to file in container
    code_file = "/workspace/script.py"
    write_code_to_container(container_id, code_file, wrapped_python_code)
    
    # Execute code with timeout
    output, error, exit_code = run_code_in_container(container_id, "python #{code_file}")
    
    # Process results
    process_execution_results(output, error, exit_code)
  ensure
    cleanup_container(container_id) if container_id
  end
  
  def execute_r
    container_id = create_container
    
    # Write code to file in container
    code_file = "/workspace/script.R"
    write_code_to_container(container_id, code_file, wrapped_r_code)
    
    # Execute code with timeout
    output, error, exit_code = run_code_in_container(container_id, "Rscript #{code_file}")
    
    # Process results
    process_execution_results(output, error, exit_code)
  ensure
    cleanup_container(container_id) if container_id
  end
  
  def execute_sql
    # SQL execution requires database connection details
    # This would connect to the specified database and run queries
    # For now, we'll implement a basic structure
    
    database_config = execution_step.analysis_request.dataset.database_config
    
    case database_config['type']
    when 'postgresql'
      execute_postgresql_query(database_config)
    when 'mysql'
      execute_mysql_query(database_config)
    when 'sqlite'
      execute_sqlite_query(database_config)
    else
      raise "Unsupported database type: #{database_config['type']}"
    end
  end
  
  def wrapped_python_code
    <<~PYTHON
      import sys
      import json
      import traceback
      import pandas as pd
      import numpy as np
      import matplotlib
      matplotlib.use('Agg')  # Non-interactive backend
      import matplotlib.pyplot as plt
      import seaborn as sns
      
      # Capture output
      import io
      from contextlib import redirect_stdout, redirect_stderr
      
      output_buffer = io.StringIO()
      error_buffer = io.StringIO()
      
      # Load datasets if provided
      datasets = #{datasets.to_json}
      for name, path in datasets.items():
          if path.endswith('.csv'):
              globals()[name] = pd.read_csv(path)
          elif path.endswith('.json'):
              globals()[name] = pd.read_json(path)
      
      # Execute user code
      try:
          with redirect_stdout(output_buffer), redirect_stderr(error_buffer):
              exec('''
      #{code}
              ''')
          
          # Save any generated plots
          for i, fig_num in enumerate(plt.get_fignums()):
              fig = plt.figure(fig_num)
              fig.savefig(f'/output/plot_{i}.png', dpi=100, bbox_inches='tight')
          
          # Output results
          result = {
              'success': True,
              'output': output_buffer.getvalue(),
              'error': error_buffer.getvalue()
          }
      except Exception as e:
          result = {
              'success': False,
              'output': output_buffer.getvalue(),
              'error': traceback.format_exc()
          }
      
      print(json.dumps(result))
    PYTHON
  end
  
  def wrapped_r_code
    <<~R
      # Capture output
      sink_file <- tempfile()
      sink(sink_file, type = "output")
      sink(sink_file, type = "message", append = TRUE)
      
      # Load libraries
      suppressPackageStartupMessages({
          library(tidyverse)
          library(ggplot2)
          library(jsonlite)
      })
      
      # Load datasets if provided
      datasets <- fromJSON('#{datasets.to_json}')
      for(name in names(datasets)) {
          path <- datasets[[name]]
          if(grepl("\\.csv$", path)) {
              assign(name, read.csv(path), envir = .GlobalEnv)
          }
      }
      
      # Execute user code
      tryCatch({
          #{code}
          
          # Save any plots
          if(length(dev.list()) > 0) {
              for(i in seq_along(dev.list())) {
                  dev.set(dev.list()[i])
                  ggsave(paste0("/output/plot_", i-1, ".png"), width = 8, height = 6, dpi = 100)
              }
          }
          
          result <- list(success = TRUE, output = "", error = "")
      }, error = function(e) {
          result <<- list(success = FALSE, output = "", error = as.character(e))
      })
      
      # Stop capturing
      sink(type = "output")
      sink(type = "message")
      
      # Read captured output
      result$output <- paste(readLines(sink_file), collapse = "\n")
      
      # Output as JSON
      cat(toJSON(result, auto_unbox = TRUE))
    R
  end
  
  def create_container
    # Build Docker image if not exists
    ensure_docker_image_exists
    
    # Create container with resource limits
    cmd = [
      'docker', 'create',
      '--memory=512m',           # Memory limit
      '--memory-swap=512m',       # No swap
      '--cpus=1',                 # CPU limit
      '--pids-limit=50',          # Process limit
      '--network=none',           # No network access
      '--read-only',              # Read-only root filesystem
      '--tmpfs', '/tmp:size=100M', # Temporary filesystem
      '-v', "#{Rails.root}/tmp/sandbox/#{execution_step.id}:/output:rw",
      'quantumquery-sandbox'
    ].join(' ')
    
    container_id = `#{cmd}`.strip
    
    # Start container
    `docker start #{container_id}`
    
    container_id
  end
  
  def ensure_docker_image_exists
    # Check if image exists
    image_exists = `docker images -q quantumquery-sandbox`.strip.present?
    
    unless image_exists
      # Build the image
      dockerfile_path = Rails.root.join('docker/sandbox/Dockerfile')
      `docker build -t quantumquery-sandbox #{dockerfile_path.dirname}`
    end
  end
  
  def write_code_to_container(container_id, file_path, content)
    # Write code to container
    Tempfile.create do |temp_file|
      temp_file.write(content)
      temp_file.flush
      
      `docker cp #{temp_file.path} #{container_id}:#{file_path}`
    end
  end
  
  def run_code_in_container(container_id, command)
    # Execute with timeout
    output = nil
    error = nil
    exit_code = nil
    
    Timeout.timeout(EXECUTION_TIMEOUT) do
      result = `docker exec #{container_id} #{command} 2>&1`
      exit_code = $?.exitstatus
      
      # Parse JSON output from wrapped code
      begin
        parsed = JSON.parse(result)
        output = parsed['output']
        error = parsed['error']
        exit_code = parsed['success'] ? 0 : 1
      rescue JSON::ParserError
        output = result
        error = ''
      end
    end
    
    [output, error, exit_code]
  rescue Timeout::Error
    # Kill the container if timeout
    `docker kill #{container_id}`
    ['', 'Execution timeout exceeded', -1]
  end
  
  def cleanup_container(container_id)
    # Stop and remove container
    `docker stop #{container_id} 2>/dev/null`
    `docker rm #{container_id} 2>/dev/null`
    
    # Clean up output directory
    output_dir = Rails.root.join("tmp/sandbox/#{execution_step.id}")
    FileUtils.rm_rf(output_dir) if output_dir.exist?
  end
  
  def process_execution_results(output, error, exit_code)
    # Check for generated files (plots, CSVs, etc.)
    output_dir = Rails.root.join("tmp/sandbox/#{execution_step.id}")
    generated_files = []
    
    if output_dir.exist?
      Dir.glob(output_dir.join('*')).each do |file|
        # Store file reference (would upload to cloud storage in production)
        generated_files << {
          name: File.basename(file),
          size: File.size(file),
          path: file
        }
      end
    end
    
    # Update execution step with results
    execution_step.update!(
      output: truncate_output(output),
      error_message: error.presence,
      exit_code: exit_code,
      metadata: execution_step.metadata.merge(
        'generated_files' => generated_files,
        'execution_successful' => exit_code == 0
      )
    )
  end
  
  def truncate_output(output)
    return output if output.bytesize <= MAX_OUTPUT_SIZE
    
    # Truncate output if too large
    truncated = output.byteslice(0, MAX_OUTPUT_SIZE)
    truncated + "\n\n[Output truncated - exceeded #{MAX_OUTPUT_SIZE / 1.megabyte}MB limit]"
  end
  
  def handle_execution_error(error)
    Rails.logger.error "Code execution failed: #{error.message}"
    Rails.logger.error error.backtrace.join("\n")
    
    execution_step.update!(
      status: 'failed',
      error_message: error.message,
      completed_at: Time.current
    )
  end
  
  def execute_postgresql_query(config)
    # Would implement PostgreSQL query execution
    # Using psql or pg gem with proper connection pooling
    raise NotImplementedError, "PostgreSQL execution coming soon"
  end
  
  def execute_mysql_query(config)
    # Would implement MySQL query execution
    # Using mysql2 gem with proper connection pooling
    raise NotImplementedError, "MySQL execution coming soon"
  end
  
  def execute_sqlite_query(config)
    # Would implement SQLite query execution
    # Using sqlite3 gem
    raise NotImplementedError, "SQLite execution coming soon"
  end
end