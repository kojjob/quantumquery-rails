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

ActiveRecord::Schema[8.0].define(version: 2025_08_29_102645) do
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
    t.datetime "completed_at"
    t.decimal "execution_time", precision: 8, scale: 3, comment: "Execution time in seconds"
    t.index ["dataset_id"], name: "index_analysis_requests_on_dataset_id"
    t.index ["organization_id"], name: "index_analysis_requests_on_organization_id"
    t.index ["user_id"], name: "index_analysis_requests_on_user_id"
  end

  create_table "api_tokens", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name"
    t.string "token"
    t.datetime "last_used_at"
    t.datetime "expires_at"
    t.datetime "revoked_at"
    t.text "scopes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token"], name: "index_api_tokens_on_token"
    t.index ["user_id"], name: "index_api_tokens_on_user_id"
  end

  create_table "api_usage_logs", force: :cascade do |t|
    t.bigint "api_token_id", null: false
    t.string "endpoint"
    t.string "ip_address"
    t.string "user_agent"
    t.integer "response_code"
    t.float "response_time"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["api_token_id"], name: "index_api_usage_logs_on_api_token_id"
  end

  create_table "comments", force: :cascade do |t|
    t.string "commentable_type", null: false
    t.bigint "commentable_id", null: false
    t.bigint "user_id", null: false
    t.text "content", null: false
    t.jsonb "metadata", default: {}
    t.boolean "edited", default: false
    t.datetime "edited_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["commentable_type", "commentable_id"], name: "index_comments_on_commentable"
    t.index ["created_at"], name: "index_comments_on_created_at"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "dashboard_widgets", force: :cascade do |t|
    t.bigint "dashboard_id", null: false
    t.string "widget_type"
    t.string "title"
    t.jsonb "config"
    t.integer "position"
    t.integer "row"
    t.integer "col"
    t.integer "width"
    t.integer "height"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["dashboard_id"], name: "index_dashboard_widgets_on_dashboard_id"
  end

  create_table "dashboards", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name"
    t.text "description"
    t.string "layout"
    t.jsonb "config"
    t.integer "position"
    t.boolean "is_default"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["is_default"], name: "index_dashboards_on_is_default"
    t.index ["user_id"], name: "index_dashboards_on_user_id"
  end

  create_table "data_source_connections", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "organization_id", null: false
    t.string "name", null: false
    t.string "source_type", null: false
    t.text "credentials_ciphertext"
    t.integer "status", default: 0, null: false
    t.datetime "last_synced_at"
    t.datetime "last_error_at"
    t.text "last_error_message"
    t.jsonb "metadata", default: {}, null: false
    t.jsonb "connection_options", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "name"], name: "index_data_source_connections_on_organization_id_and_name", unique: true
    t.index ["organization_id", "source_type"], name: "idx_on_organization_id_source_type_f398c53d5d"
    t.index ["organization_id"], name: "index_data_source_connections_on_organization_id"
    t.index ["status"], name: "index_data_source_connections_on_status"
    t.index ["user_id"], name: "index_data_source_connections_on_user_id"
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
    t.integer "created_by_id"
    t.jsonb "metadata", default: {}
    t.datetime "last_connected_at"
    t.index ["created_by_id"], name: "index_datasets_on_created_by_id"
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

  create_table "query_caches", force: :cascade do |t|
    t.string "query_hash", null: false
    t.text "query_text", null: false
    t.bigint "dataset_id", null: false
    t.bigint "organization_id", null: false
    t.jsonb "results", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "expires_at"
    t.integer "access_count", default: 0, null: false
    t.bigint "cache_size_bytes", default: 0, null: false
    t.string "cache_key"
    t.string "ai_model"
    t.float "query_execution_time"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "accessed_at"
    t.index ["accessed_at"], name: "index_query_caches_on_accessed_at"
    t.index ["cache_key"], name: "index_query_caches_on_cache_key"
    t.index ["dataset_id"], name: "index_query_caches_on_dataset_id"
    t.index ["expires_at"], name: "index_query_caches_on_expires_at"
    t.index ["organization_id", "created_at"], name: "index_query_caches_on_organization_id_and_created_at"
    t.index ["organization_id"], name: "index_query_caches_on_organization_id"
    t.index ["query_hash"], name: "index_query_caches_on_query_hash", unique: true
  end

  create_table "scheduled_reports", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "organization_id", null: false
    t.bigint "dataset_id"
    t.string "name", null: false
    t.text "query", null: false
    t.string "frequency", default: "weekly", null: false
    t.integer "schedule_day"
    t.integer "schedule_hour", default: 9
    t.text "recipients"
    t.string "format", default: "pdf"
    t.boolean "enabled", default: true
    t.datetime "last_run_at"
    t.datetime "next_run_at"
    t.integer "run_count", default: 0
    t.text "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["dataset_id"], name: "index_scheduled_reports_on_dataset_id"
    t.index ["enabled"], name: "index_scheduled_reports_on_enabled"
    t.index ["next_run_at"], name: "index_scheduled_reports_on_next_run_at"
    t.index ["organization_id"], name: "index_scheduled_reports_on_organization_id"
    t.index ["user_id", "enabled"], name: "index_scheduled_reports_on_user_id_and_enabled"
    t.index ["user_id"], name: "index_scheduled_reports_on_user_id"
  end

  create_table "share_links", force: :cascade do |t|
    t.bigint "analysis_request_id", null: false
    t.bigint "created_by_id", null: false
    t.string "token", null: false
    t.datetime "expires_at"
    t.integer "access_count", default: 0
    t.integer "view_count", default: 0
    t.integer "max_views"
    t.string "password_digest"
    t.boolean "active", default: true
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_share_links_on_active"
    t.index ["analysis_request_id"], name: "index_share_links_on_analysis_request_id"
    t.index ["created_by_id"], name: "index_share_links_on_created_by_id"
    t.index ["token"], name: "index_share_links_on_token", unique: true
  end

  create_table "team_memberships", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "user_id", null: false
    t.integer "role", default: 0, null: false
    t.bigint "invited_by_id"
    t.datetime "accepted_at"
    t.string "invitation_token"
    t.datetime "invitation_expires_at"
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_team_memberships_on_active"
    t.index ["invitation_token"], name: "index_team_memberships_on_invitation_token", unique: true
    t.index ["organization_id", "user_id"], name: "index_team_memberships_on_organization_id_and_user_id", unique: true
    t.index ["organization_id"], name: "index_team_memberships_on_organization_id"
    t.index ["user_id"], name: "index_team_memberships_on_user_id"
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
    t.string "encrypted_otp_secret"
    t.string "encrypted_otp_secret_iv"
    t.string "encrypted_otp_secret_salt"
    t.integer "consumed_timestep"
    t.boolean "otp_required_for_login", default: false, null: false
    t.text "otp_backup_codes", array: true
    t.datetime "two_factor_enabled_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["encrypted_otp_secret"], name: "index_users_on_encrypted_otp_secret", unique: true
    t.index ["organization_id"], name: "index_users_on_organization_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "analysis_requests", "datasets"
  add_foreign_key "analysis_requests", "organizations"
  add_foreign_key "analysis_requests", "users"
  add_foreign_key "api_tokens", "users"
  add_foreign_key "api_usage_logs", "api_tokens"
  add_foreign_key "comments", "users"
  add_foreign_key "dashboard_widgets", "dashboards"
  add_foreign_key "dashboards", "users"
  add_foreign_key "data_source_connections", "organizations"
  add_foreign_key "data_source_connections", "users"
  add_foreign_key "datasets", "organizations"
  add_foreign_key "datasets", "users", column: "created_by_id"
  add_foreign_key "execution_steps", "analysis_requests"
  add_foreign_key "query_caches", "datasets"
  add_foreign_key "query_caches", "organizations"
  add_foreign_key "scheduled_reports", "datasets"
  add_foreign_key "scheduled_reports", "organizations"
  add_foreign_key "scheduled_reports", "users"
  add_foreign_key "share_links", "analysis_requests"
  add_foreign_key "share_links", "users", column: "created_by_id"
  add_foreign_key "team_memberships", "organizations"
  add_foreign_key "team_memberships", "users"
  add_foreign_key "team_memberships", "users", column: "invited_by_id"
  add_foreign_key "users", "organizations"
end
