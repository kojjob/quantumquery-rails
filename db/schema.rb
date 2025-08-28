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

ActiveRecord::Schema[8.0].define(version: 2025_08_28_012541) do
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
    t.index ["dataset_id"], name: "index_analysis_requests_on_dataset_id"
    t.index ["organization_id"], name: "index_analysis_requests_on_organization_id"
    t.index ["user_id"], name: "index_analysis_requests_on_user_id"
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
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["organization_id"], name: "index_users_on_organization_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "analysis_requests", "datasets"
  add_foreign_key "analysis_requests", "organizations"
  add_foreign_key "analysis_requests", "users"
  add_foreign_key "comments", "users"
  add_foreign_key "datasets", "organizations"
  add_foreign_key "datasets", "users", column: "created_by_id"
  add_foreign_key "execution_steps", "analysis_requests"
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
