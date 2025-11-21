# frozen_string_literal: true

require "test_helper"

class AnalysisPlanParserTest < ActiveSupport::TestCase
  # Valid JSON plan
  test "parses valid JSON plan successfully" do
    json_plan = {
      "steps" => [
        {
          "type" => "data_exploration",
          "language" => "python",
          "description" => "Explore dataset structure"
        },
        {
          "type" => "statistical_analysis",
          "language" => "r",
          "description" => "Perform statistical tests"
        }
      ]
    }.to_json

    parser = AnalysisPlanParser.new(json_plan)
    plan = parser.parse

    assert parser.valid?
    assert_equal 2, plan["steps"].length
    assert_equal "data_exploration", plan["steps"][0]["type"]
    assert_equal "python", plan["steps"][0]["language"]
  end

  # JSON in markdown code block
  test "extracts JSON from markdown code block" do
    markdown = <<~MD
      Here's the analysis plan:
      
      ```json
      {
        "steps": [
          {
            "type": "visualization",
            "language": "python",
            "description": "Create charts"
          }
        ]
      }
      ```
      
      This plan will help analyze the data.
    MD

    parser = AnalysisPlanParser.new(markdown)
    plan = parser.parse

    assert parser.valid?
    assert_equal 1, plan["steps"].length
    assert_equal "visualization", plan["steps"][0]["type"]
  end

  # JSON embedded in text
  test "extracts JSON object from plain text" do
    text = <<~TEXT
      Based on your query, I've created this plan:
      {"steps": [{"type": "data_cleaning", "language": "python", "description": "Clean data"}]}
      Let me know if you need changes.
    TEXT

    parser = AnalysisPlanParser.new(text)
    plan = parser.parse

    assert parser.valid?
    assert_equal 1, plan["steps"].length
  end

  # Array of steps (no wrapper object)
  test "handles array of steps directly" do
    json_array = [
      { "type" => "feature_engineering", "language" => "python", "description" => "Create features" },
      { "type" => "model_training", "language" => "python", "description" => "Train model" }
    ].to_json

    parser = AnalysisPlanParser.new(json_array)
    plan = parser.parse

    assert parser.valid?
    assert_equal 2, plan["steps"].length
  end

  # Nested plan structure
  test "handles nested plan structure" do
    nested = {
      "analysis_plan" => {
        "steps" => [
          { "type" => "hypothesis_testing", "language" => "r", "description" => "Test hypothesis" }
        ],
        "metadata" => { "complexity" => "high" }
      }
    }.to_json

    parser = AnalysisPlanParser.new(nested)
    plan = parser.parse

    assert parser.valid?
    assert_equal 1, plan["steps"].length
    assert_equal "high", plan["metadata"]["complexity"]
  end

  # Trailing commas (invalid JSON but common)
  test "fixes trailing commas in JSON" do
    invalid_json = <<~JSON
      {
        "steps": [
          {
            "type": "data_exploration",
            "language": "python",
            "description": "Explore data",
          },
        ],
      }
    JSON

    parser = AnalysisPlanParser.new(invalid_json)
    plan = parser.parse

    assert parser.valid?
    assert_includes parser.warnings, "JSON required automatic fixing"
  end

  # Comments in JSON (invalid but sometimes generated)
  test "removes comments from JSON" do
    json_with_comments = <<~JSON
      {
        // This is the analysis plan
        "steps": [
          {
            "type": "clustering", // K-means clustering
            "language": "python",
            "description": "Perform clustering"
          }
        ]
      }
    JSON

    parser = AnalysisPlanParser.new(json_with_comments)
    plan = parser.parse

    assert parser.valid?
    assert_equal "clustering", plan["steps"][0]["type"]
  end

  # Missing required fields
  test "detects missing required fields" do
    incomplete = {
      "steps" => [
        {
          "type" => "visualization"
          # Missing: language, description
        }
      ]
    }.to_json

    parser = AnalysisPlanParser.new(incomplete)
    parser.parse

    assert_not parser.valid?
    assert parser.errors.any? { |e| e.include?("language") }
    assert parser.errors.any? { |e| e.include?("description") }
  end

  # Empty steps array
  test "rejects empty steps array" do
    empty_plan = { "steps" => [] }.to_json

    parser = AnalysisPlanParser.new(empty_plan)
    parser.parse

    assert_not parser.valid?
    assert parser.errors.any? { |e| e.include?("at least one step") }
  end

  # Unsupported language
  test "rejects unsupported language" do
    invalid_lang = {
      "steps" => [
        {
          "type" => "data_exploration",
          "language" => "javascript",
          "description" => "Explore with JS"
        }
      ]
    }.to_json

    parser = AnalysisPlanParser.new(invalid_lang)
    parser.parse

    assert_not parser.valid?
    assert parser.errors.any? { |e| e.include?("Unsupported language") }
  end

  # Unknown step type (warning only)
  test "warns about unknown step type but accepts it" do
    unknown_type = {
      "steps" => [
        {
          "type" => "custom_analysis",
          "language" => "python",
          "description" => "Custom step"
        }
      ]
    }.to_json

    parser = AnalysisPlanParser.new(unknown_type)
    plan = parser.parse

    assert parser.valid?
    assert parser.warnings.any? { |w| w.include?("Unknown step type") }
  end

  # Field name variations
  test "handles field name variations" do
    variations = {
      "steps" => [
        {
          "step_type" => "correlation_analysis",
          "lang" => "R",
          "desc" => "Correlation matrix"
        }
      ]
    }.to_json

    parser = AnalysisPlanParser.new(variations)
    plan = parser.parse

    assert parser.valid?
    assert_equal "correlation_analysis", plan["steps"][0]["type"]
    assert_equal "r", plan["steps"][0]["language"]
    assert_equal "Correlation matrix", plan["steps"][0]["description"]
  end

  # Sequence numbers
  test "assigns sequence numbers to steps" do
    plan_json = {
      "steps" => [
        { "type" => "data_exploration", "language" => "python", "description" => "Step 1" },
        { "type" => "visualization", "language" => "python", "description" => "Step 2" },
        { "type" => "statistical_analysis", "language" => "r", "description" => "Step 3" }
      ]
    }.to_json

    parser = AnalysisPlanParser.new(plan_json)
    plan = parser.parse

    assert parser.valid?
    assert_equal 0, plan["steps"][0]["sequence_number"]
    assert_equal 1, plan["steps"][1]["sequence_number"]
    assert_equal 2, plan["steps"][2]["sequence_number"]
  end

  # Dependencies validation
  test "validates step dependencies" do
    with_deps = {
      "steps" => [
        { "type" => "data_cleaning", "language" => "python", "description" => "Clean" },
        { 
          "type" => "visualization", 
          "language" => "python", 
          "description" => "Visualize",
          "dependencies" => [0]
        }
      ]
    }.to_json

    parser = AnalysisPlanParser.new(with_deps)
    plan = parser.parse

    assert parser.valid?
    assert_equal [0], plan["steps"][1]["dependencies"]
  end

  # Invalid dependencies
  test "rejects invalid dependencies" do
    invalid_deps = {
      "steps" => [
        { 
          "type" => "visualization", 
          "language" => "python", 
          "description" => "Visualize",
          "dependencies" => [5] # References non-existent step
        }
      ]
    }.to_json

    parser = AnalysisPlanParser.new(invalid_deps)
    parser.parse

    assert_not parser.valid?
    assert parser.errors.any? { |e| e.include?("Invalid dependency") }
  end

  # Malformed JSON
  test "handles completely malformed JSON" do
    malformed = "This is not JSON at all! {broken: 'json'}"

    parser = AnalysisPlanParser.new(malformed)
    plan = parser.parse

    assert_nil plan
    assert_not parser.valid?
    assert parser.errors.any?
  end

  # Empty or nil input
  test "handles empty input" do
    parser = AnalysisPlanParser.new("")
    plan = parser.parse

    assert_nil plan
    assert_not parser.valid?
  end

  test "handles nil input" do
    parser = AnalysisPlanParser.new(nil)
    plan = parser.parse

    assert_nil plan
    assert_not parser.valid?
  end

  # parse! raises on error
  test "parse! raises error on invalid input" do
    invalid = { "steps" => [] }.to_json
    parser = AnalysisPlanParser.new(invalid)

    assert_raises(AnalysisPlanParser::ParseError) do
      parser.parse!
    end
  end

  # Optional fields preserved
  test "preserves optional fields" do
    with_optional = {
      "steps" => [
        {
          "type" => "model_training",
          "language" => "python",
          "description" => "Train model",
          "timeout" => 300,
          "code_template" => "model = train(X, y)",
          "expected_output" => "trained_model.pkl"
        }
      ],
      "reasoning" => "This approach is optimal because..."
    }.to_json

    parser = AnalysisPlanParser.new(with_optional)
    plan = parser.parse

    assert parser.valid?
    assert_equal 300, plan["steps"][0]["timeout"]
    assert plan["steps"][0]["code_template"].present?
    assert plan["reasoning"].present?
  end

  # Very long description
  test "warns about very long descriptions" do
    long_desc = "A" * 600
    with_long_desc = {
      "steps" => [
        {
          "type" => "data_exploration",
          "language" => "python",
          "description" => long_desc
        }
      ]
    }.to_json

    parser = AnalysisPlanParser.new(with_long_desc)
    plan = parser.parse

    assert parser.valid?
    assert parser.warnings.any? { |w| w.include?("very long") }
  end

  # Multiple JSON objects (takes first)
  test "extracts first JSON object when multiple present" do
    multiple = <<~TEXT
      First plan: {"steps": [{"type": "data_exploration", "language": "python", "description": "First"}]}
      Second plan: {"steps": [{"type": "visualization", "language": "python", "description": "Second"}]}
    TEXT

    parser = AnalysisPlanParser.new(multiple)
    plan = parser.parse

    assert parser.valid?
    assert_equal "data_exploration", plan["steps"][0]["type"]
  end

  # Case insensitive language normalization
  test "normalizes language to lowercase" do
    mixed_case = {
      "steps" => [
        { "type" => "data_exploration", "language" => "Python", "description" => "Explore" },
        { "type" => "visualization", "language" => "R", "description" => "Visualize" }
      ]
    }.to_json

    parser = AnalysisPlanParser.new(mixed_case)
    plan = parser.parse

    assert parser.valid?
    assert_equal "python", plan["steps"][0]["language"]
    assert_equal "r", plan["steps"][1]["language"]
  end
end
