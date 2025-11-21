# frozen_string_literal: true

require "docker"

module CodeExecution
  # Base class for executing code in Docker containers
  # Provides common functionality for container lifecycle management,
  # resource limits, timeout handling, and result collection
  class BaseExecutor
    # Execution result structure
    ExecutionResult = Struct.new(
      :success,
      :output,
      :error,
      :exit_code,
      :duration_seconds,
      :metadata,
      keyword_init: true
    ) do
      def success?
        success
      end

      def failed?
        !success
      end
    end

    attr_reader :code, :options, :container

    # Default resource limits
    DEFAULT_MEMORY_LIMIT = 512 * 1024 * 1024  # 512MB
    DEFAULT_CPU_SHARES = 512                   # 50% of one CPU
    DEFAULT_TIMEOUT = 60                       # 60 seconds
    DEFAULT_NETWORK_MODE = "none"              # No network access

    def initialize(code, options = {})
      @code = code
      @options = options
      @container = nil
      @start_time = nil

      # Configure Docker
      Docker.url = ENV.fetch("DOCKER_HOST", "unix:///var/run/docker.sock")
    end

    # Main execution method - override in subclasses if needed
    def execute
      @start_time = Time.current

      begin
        # Create container
        create_container

        # Start container
        start_container

        # Wait for execution to complete with timeout
        wait_for_completion

        # Collect results
        collect_results
      rescue Docker::Error::TimeoutError => e
        handle_timeout
      rescue => e
        handle_error(e)
      ensure
        cleanup
      end
    end

    protected

    # Override in subclasses to specify the Docker image
    def image_name
      raise NotImplementedError, "#{self.class} must implement image_name"
    end

    # Override in subclasses to prepare code for execution
    def prepare_code
      @code
    end

    # Override in subclasses to specify the command to run
    def execution_command
      raise NotImplementedError, "#{self.class} must implement execution_command"
    end

    def create_container
      prepared_code = prepare_code

      # Ensure image is available
      pull_image_if_needed

      # Container configuration
      config = {
        "Image" => image_name,
        "Cmd" => execution_command,
        "Tty" => false,
        "AttachStdout" => true,
        "AttachStderr" => true,
        "NetworkDisabled" => network_disabled?,
        "HostConfig" => {
          "Memory" => memory_limit,
          "MemorySwap" => memory_limit, # Disable swap
          "CpuShares" => cpu_shares,
          "PidsLimit" => 100, # Limit number of processes
          "NetworkMode" => network_mode,
          "ReadonlyRootfs" => false, # Allow writing to /tmp
          "Tmpfs" => {
            "/tmp" => "rw,noexec,nosuid,size=100m"
          },
          "Binds" => binds,
          "CapDrop" => ["ALL"], # Drop all capabilities
          "SecurityOpt" => ["no-new-privileges"]
        },
        "Env" => environment_variables
      }

      @container = Docker::Container.create(config)
      Rails.logger.info "Created container #{@container.id[0..11]} for code execution"
    end

    def start_container
      @container.start
      Rails.logger.info "Started container #{@container.id[0..11]}"
    end

    def wait_for_completion
      timeout = options[:timeout] || DEFAULT_TIMEOUT
      
      # Wait for container with timeout
      @container.wait(timeout)
    rescue Docker::Error::TimeoutError
      raise
    end

    def collect_results
      # Get logs (stdout and stderr)
      stdout = @container.logs(stdout: true)
      stderr = @container.logs(stderr: true)

      # Get exit code
      container_info = @container.json
      exit_code = container_info["State"]["ExitCode"]

      # Calculate duration
      duration = Time.current - @start_time

      # Determine success
      success = exit_code == 0 && stderr.empty?

      ExecutionResult.new(
        success: success,
        output: stdout,
        error: stderr,
        exit_code: exit_code,
        duration_seconds: duration,
        metadata: {
          container_id: @container.id,
          image: image_name,
          memory_limit: memory_limit,
          cpu_shares: cpu_shares,
          timeout: timeout
        }
      )
    end

    def handle_timeout
      Rails.logger.error "Container execution timeout after #{timeout_seconds}s"
      
      duration = Time.current - @start_time

      ExecutionResult.new(
        success: false,
        output: "",
        error: "Execution timeout after #{timeout_seconds} seconds",
        exit_code: 124, # Timeout exit code
        duration_seconds: duration,
        metadata: {
          container_id: @container&.id,
          timeout: true
        }
      )
    end

    def handle_error(error)
      Rails.logger.error "Container execution error: #{error.message}"
      Rails.logger.error error.backtrace.join("\n")

      duration = @start_time ? Time.current - @start_time : 0

      ExecutionResult.new(
        success: false,
        output: "",
        error: "Execution error: #{error.message}",
        exit_code: -1,
        duration_seconds: duration,
        metadata: {
          error_class: error.class.name,
          error_message: error.message
        }
      )
    end

    def cleanup
      return unless @container

      begin
        # Stop container if still running
        @container.stop("timeout" => 5) if container_running?
        
        # Remove container
        @container.delete(force: true)
        
        Rails.logger.info "Cleaned up container #{@container.id[0..11]}"
      rescue => e
        Rails.logger.error "Error cleaning up container: #{e.message}"
      end
    end

    def container_running?
      return false unless @container
      
      info = @container.json
      info["State"]["Running"]
    rescue
      false
    end

    def pull_image_if_needed
      begin
        Docker::Image.get(image_name)
      rescue Docker::Error::NotFoundError
        Rails.logger.info "Pulling image #{image_name}..."
        Docker::Image.create("fromImage" => image_name)
        Rails.logger.info "Successfully pulled #{image_name}"
      end
    end

    # Configuration helpers
    def memory_limit
      options[:memory_limit] || DEFAULT_MEMORY_LIMIT
    end

    def cpu_shares
      options[:cpu_shares] || DEFAULT_CPU_SHARES
    end

    def timeout_seconds
      options[:timeout] || DEFAULT_TIMEOUT
    end

    def network_mode
      options[:network_mode] || DEFAULT_NETWORK_MODE
    end

    def network_disabled?
      network_mode == "none"
    end

    def binds
      # Override in subclasses to mount volumes
      options[:binds] || []
    end

    def environment_variables
      # Override in subclasses to set environment variables
      options[:env] || []
    end
  end
end
