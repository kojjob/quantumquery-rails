# frozen_string_literal: true

module CodeExecution
  # Executes R code in a sandboxed Docker container
  # Pre-configured with tidyverse, ggplot2, caret, etc.
  class RExecutor < BaseExecutor
    R_IMAGE = "quantumquery/r-executor:latest"
    
    protected

    def image_name
      R_IMAGE
    end

    def prepare_code
      # Write code to a temp file that will be mounted
      @code_file = Tempfile.new(["code", ".R"])
      @code_file.write(code)
      @code_file.close
      
      @code_file.path
    end

    def execution_command
      ["Rscript", "/workspace/code.R"]
    end

    def binds
      binds = []
      
      # Mount code file
      if @code_file
        binds << "#{@code_file.path}:/workspace/code.R:ro"
      end

      # Mount dataset file if provided
      if options[:dataset_path] && File.exist?(options[:dataset_path])
        dataset_filename = File.basename(options[:dataset_path])
        binds << "#{options[:dataset_path]}:/workspace/data/#{dataset_filename}:ro"
      end

      # Mount output directory for generated files (plots, etc.)
      if options[:output_dir]
        FileUtils.mkdir_p(options[:output_dir])
        binds << "#{options[:output_dir]}:/workspace/output:rw"
      end

      binds
    end

    def environment_variables
      env = []

      # Pass dataset filename if provided
      if options[:dataset_path]
        dataset_filename = File.basename(options[:dataset_path])
        env << "DATASET_FILE=/workspace/data/#{dataset_filename}"
      end

      # Set R environment variables
      env << "R_LIBS_USER=/usr/local/lib/R/site-library"

      env
    end

    def cleanup
      super
      
      # Clean up temp files
      @code_file&.unlink rescue nil
    end

    def collect_results
      result = super

      # Check for generated files in output directory (plots, data files, etc.)
      if options[:output_dir] && Dir.exist?(options[:output_dir])
        generated_files = Dir.glob(File.join(options[:output_dir], "*")).map do |path|
          {
            filename: File.basename(path),
            size: File.size(path),
            path: path,
            type: File.extname(path)
          }
        end
        result.metadata[:generated_files] = generated_files
      end

      result
    end
  end
end
