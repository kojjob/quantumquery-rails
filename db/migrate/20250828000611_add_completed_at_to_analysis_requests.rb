class AddCompletedAtToAnalysisRequests < ActiveRecord::Migration[8.0]
  def change
    add_column :analysis_requests, :completed_at, :datetime
  end
end
