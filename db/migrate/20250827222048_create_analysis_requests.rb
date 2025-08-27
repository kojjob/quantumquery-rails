class CreateAnalysisRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :analysis_requests do |t|
      t.references :user, null: false, foreign_key: true
      t.references :dataset, null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: true
      t.text :natural_language_query
      t.jsonb :analyzed_intent
      t.jsonb :data_requirements
      t.integer :status, default: 0
      t.float :complexity_score
      t.jsonb :metadata, default: {}
      t.text :error_message

      t.timestamps
    end
  end
end
