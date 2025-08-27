class CreateExecutionSteps < ActiveRecord::Migration[8.0]
  def change
    create_table :execution_steps do |t|
      t.references :analysis_request, null: false, foreign_key: true
      t.integer :step_type
      t.integer :language
      t.text :generated_code
      t.integer :status
      t.datetime :started_at
      t.datetime :completed_at
      t.text :error_message
      t.jsonb :result_data
      t.jsonb :resource_usage

      t.timestamps
    end
  end
end
