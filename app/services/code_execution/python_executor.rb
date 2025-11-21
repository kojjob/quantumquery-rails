# frozen_string_literal: true

module CodeExecution
  # Executes Python code in a sandboxed Docker container
  # Pre-configured with pandas, numpy, scikit-learn, matplotlib, etc.
  class PythonExecutor < BaseExecutor
    PYTHON_IMAGE = "quantumquery/python-executor:latest"
    
    protected

    def image_name
      PYTHON_IMAGE
    end

    def prepare_code
      # Write code to a temp file that will be mounted
      @code_file = Tempfile.new(["code", ".py"])
      @code_file.write(code)
      @code_file.close
      
      @code_file.path
    end

    def execution_command
      ["python", "/workspace/code.py"]
    end

    def binds
      binds = []
      
      # Mount code file
      if @code_file
        binds << "#{@code_file.path}:/workspace/code.py:ro"
      end

      # Mount dataset file if provided
      if options[:dataset_path] && File.exist?(options[:dataset_path])
        dataset_filename = File.basename(options[:dataset_path])
        binds << "#{options[:dataset_path]}:/workspace/data/#{dataset_filename}:ro"
      end

      # Mount output directory for generated files
      if options[:output_dir]
        FileUtils.mkdir_p(options[:output_dir])
        binds << "#{options[:output_dir]}:/workspace/output:rw"
      end

      binds
    end

    def environment_variables
      env = [
        "PYTHONUNBUFFERED=1",
        "MPLBACKEND=Agg" # Non-interactive matplotlib backend
      ]

      # Pass dataset filename if provided
      if options[:dataset_path]
        dataset_filename = File.basename(options[:dataset_path])
        env << "DATASET_FILE=/workspace/data/#{dataset_filename}"
      end

      env
    end

    def cleanup
      super
      
      # Clean up temp files
      @code_file&.unlink rescue nil
    end

    # Helper to parse Python execution results
    def collect_results
      result = super

      # Try to parse structured output (e.g., JSON results)
      if result.success? && result.output.present?
        begin
          # Check if output contains JSON
          if result.output.strip.start_with?("{") || result.output.strip.start_with?("[")
            parsed = JSON.parse(result.output)
            result.metadata[:parsed_output] = parsed
          end
        rescue JSON::ParserError
          # Not JSON, keep as plain text
        end
      end

      # Check for generated files in output directory
      if options[:output_dir] && Dir.exist?(options[:output_dir])
        generated_files = Dir.glob(File.join(options[:output_dir], "*")).map do |path|
          {
            filename: File.basename(path),
            size: File.size(path),
            path: path
          }
        end
        result.metadata[:generated_files] = generated_files
      end

      result
    end
  end
end
