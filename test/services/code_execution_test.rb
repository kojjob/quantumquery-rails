# frozen_string_literal: true

require "test_helper"

class CodeExecutionTest < ActiveSupport::TestCase
  # Note: These tests require Docker to be running
  # Skip if Docker is not available
  
  setup do
    skip "Docker not available" unless docker_available?
    @organization = organizations(:one)
  end

  # Python Executor Tests
  test "python executor executes simple code successfully" do
    code = <<~PYTHON
      import pandas as pd
      result = {"sum": 1 + 2, "product": 3 * 4}
      print(result)
    PYTHON

    executor = CodeExecution::PythonExecutor.new(code, timeout: 10)
    result = executor.execute

    assert result.success?
    assert_equal 0, result.exit_code
    assert result.output.present?
  end

  test "python executor enforces timeout" do
    code = <<~PYTHON
      import time
      time.sleep(100)  # Sleep longer than timeout
      print("Done")
    PYTHON

    executor = CodeExecution::PythonExecutor.new(code, timeout: 2)
    result = executor.execute

    assert result.failed?
    assert_match(/timeout/i, result.error.downcase)
  end

  test "python executor handles errors gracefully" do
    code = <<~PYTHON
      # This will cause a NameError
      print(undefined_variable)
    PYTHON

    executor = CodeExecution::PythonExecutor.new(code, timeout: 10)
    result = executor.execute

    assert result.failed?
    assert result.error.present?
  end

  test "python executor mounts dataset file" do
    # Create a temp CSV file
    csv_content = "name,value\ntest,123\n"
    dataset_file = Tempfile.new(["dataset", ".csv"])
    dataset_file.write(csv_content)
    dataset_file.close

    code = <<~PYTHON
      import pandas as pd
      import os
      
      dataset_path = os.environ.get('DATASET_FILE')
      if dataset_path and os.path.exists(dataset_path):
        df = pd.read_csv(dataset_path)
        print(f"Loaded {len(df)} rows")
      else:
        print("No dataset found")
    PYTHON

    executor = CodeExecution::PythonExecutor.new(
      code,
      timeout: 10,
      dataset_path: dataset_file.path
    )
    result = executor.execute

    assert result.success?
    assert_match(/Loaded 1 rows/, result.output)

    dataset_file.unlink
  end

  # R Executor Tests
  test "r executor executes simple code successfully" do
    code = <<~R
      result <- 1 + 2
      print(paste("Result:", result))
    R

    executor = CodeExecution::RExecutor.new(code, timeout: 10)
    result = executor.execute

    assert result.success?
    assert_equal 0, result.exit_code
    assert result.output.present?
  end

  test "r executor enforces timeout" do
    code = <<~R
      Sys.sleep(100)  # Sleep longer than timeout
      print("Done")
    R

    executor = CodeExecution::RExecutor.new(code, timeout: 2)
    result = executor.execute

    assert result.failed?
    assert_match(/timeout/i, result.error.downcase)
  end

  # SQL Executor Tests  
  test "sql executor requires dataset" do
    code = "SELECT 1"

    executor = CodeExecution::SqlExecutor.new(code)
    result = executor.execute

    assert result.failed?
    assert_match(/dataset is required/i, result.error)
  end

  test "sql executor validates dataset connection" do
    dataset = Dataset.create!(
      organization: @organization,
      name: "Test DB",
      data_source_type: :postgresql,
      status: :pending
    )

    code = "SELECT 1"
    
    executor = CodeExecution::SqlExecutor.new(code, dataset: dataset)
    result = executor.execute

    assert result.failed?
    assert_match(/not connected/i, result.error)
  end

  # Factory Tests
  test "factory builds python executor" do
    executor = CodeExecution::ExecutorFactory.build(:python, "print('test')")
    assert_instance_of CodeExecution::PythonExecutor, executor
  end

  test "factory builds r executor" do
    executor = CodeExecution::ExecutorFactory.build(:r, "print('test')")
    assert_instance_of CodeExecution::RExecutor, executor
  end

  test "factory builds sql executor" do
    executor = CodeExecution::ExecutorFactory.build(:sql, "SELECT 1")
    assert_instance_of CodeExecution::SqlExecutor, executor
  end

  test "factory raises for unsupported language" do
    assert_raises RuntimeError do
      CodeExecution::ExecutorFactory.build(:javascript, "console.log('test')")
    end
  end

  test "factory checks language support" do
    assert CodeExecution::ExecutorFactory.supported?(:python)
    assert CodeExecution::ExecutorFactory.supported?(:r)
    assert CodeExecution::ExecutorFactory.supported?(:sql)
    assert_not CodeExecution::ExecutorFactory.supported?(:javascript)
  end

  # Integration Tests
  test "execution result provides comprehensive information" do
    code = "print('Hello, World!')"

    executor = CodeExecution::PythonExecutor.new(code, timeout: 10)
    result = executor.execute

    # Check result structure
    assert_respond_to result, :success?
    assert_respond_to result, :failed?
    assert_not_nil result.output
    assert_not_nil result.error
    assert_not_nil result.exit_code
    assert_not_nil result.duration_seconds
    assert_not_nil result.metadata
  end

  test "executor cleans up containers after execution" do
    code = "print('test')"

    executor = CodeExecution::PythonExecutor.new(code, timeout: 10)
    result = executor.execute

    # Container should be removed
    container_id = result.metadata[:container_id]
    
    # Try to get container - should raise NotFound error
    assert_raises Docker::Error::NotFoundError do
      Docker::Container.get(container_id)
    end
  end

  test "executor cleans up containers even on error" do
    code = "raise Exception('test error')"

    executor = CodeExecution::PythonExecutor.new(code, timeout: 10)
    result = executor.execute

    assert result.failed?
    
    # Container should still be cleaned up
    if result.metadata[:container_id]
      assert_raises Docker::Error::NotFoundError do
        Docker::Container.get(result.metadata[:container_id])
      end
    end
  end

  # Code Execution Job Tests
  test "code execution job processes successful execution" do
    analysis_request = analysis_requests(:one)
    
    step = ExecutionStep.create!(
      analysis_request: analysis_request,
      step_number: 1,
      step_type: "exploration",
      language: "python",
      generated_code: "print('test')",
      status: :executing
    )

    skip "Requires Docker" unless docker_available?

    CodeExecutionJob.perform_now(step)

    step.reload
    assert_equal "completed", step.status
    assert step.result_data.present?
  end

  test "code execution job handles execution errors" do
    analysis_request = analysis_requests(:one)
    
    step = ExecutionStep.create!(
      analysis_request: analysis_request,
      step_number: 1,
      step_type: "exploration",
      language: "python",
      generated_code: "undefined_variable",
      status: :executing
    )

    skip "Requires Docker" unless docker_available?

    CodeExecutionJob.perform_now(step)

    step.reload
    assert_equal "failed", step.status
    assert step.error_message.present?
  end

  private

  def docker_available?
    Docker.version
    true
  rescue
    false
  end
end
