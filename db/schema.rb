# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_08_27_222057) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "analysis_requests", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "dataset_id", null: false
    t.bigint "organization_id", null: false
    t.text "natural_language_query"
    t.jsonb "analyzed_intent"
    t.jsonb "data_requirements"
    t.integer "status", default: 0
    t.float "complexity_score"
    t.jsonb "metadata", default: {}
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["dataset_id"], name: "index_analysis_requests_on_dataset_id"
    t.index ["organization_id"], name: "index_analysis_requests_on_organization_id"
    t.index ["user_id"], name: "index_analysis_requests_on_user_id"
  end

  create_table "datasets", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "name"
    t.text "description"
    t.string "data_source_type"
    t.jsonb "connection_config"
    t.jsonb "schema_metadata"
    t.integer "status", default: 0
    t.text "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_datasets_on_organization_id"
  end

  create_table "execution_steps", force: :cascade do |t|
    t.bigint "analysis_request_id", null: false
    t.integer "step_type"
    t.integer "language"
    t.text "generated_code"
    t.integer "status"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.text "error_message"
    t.jsonb "result_data"
    t.jsonb "resource_usage"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["analysis_request_id"], name: "index_execution_steps_on_analysis_request_id"
  end

  create_table "organizations", force: :cascade do |t|
    t.string "name"
    t.string "slug"
    t.jsonb "settings"
    t.integer "subscription_tier"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.bigint "organization_id"
    t.string "first_name"
    t.string "last_name"
    t.integer "subscription_tier", default: 0
    t.integer "technical_level", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["organization_id"], name: "index_users_on_organization_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "analysis_requests", "datasets"
  add_foreign_key "analysis_requests", "organizations"
  add_foreign_key "analysis_requests", "users"
  add_foreign_key "datasets", "organizations"
  add_foreign_key "execution_steps", "analysis_requests"
  add_foreign_key "users", "organizations"
end
