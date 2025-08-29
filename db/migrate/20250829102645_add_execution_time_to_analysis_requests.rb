class AddExecutionTimeToAnalysisRequests < ActiveRecord::Migration[8.0]
  def change
    add_column :analysis_requests, :execution_time, :decimal, precision: 8, scale: 3, comment: "Execution time in seconds"
  end
end
