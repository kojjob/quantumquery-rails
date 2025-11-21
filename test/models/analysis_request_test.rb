require "test_helper"

class AnalysisRequestTest < ActiveSupport::TestCase
  test "should validate natural language query presence" do
    request = AnalysisRequest.new
    assert_not request.valid?
    assert_includes request.errors[:natural_language_query], "can't be blank"
  end

  test "should validate minimum query length" do
    request = build_analysis_request(natural_language_query: "Short")
    assert_not request.valid?
    assert_includes request.errors[:natural_language_query], "is too short (minimum is 10 characters)"
  end

  test "should transition through analysis states" do
    request = create_analysis_request
    
    assert request.pending?
    
    request.start_analysis!
    assert request.analyzing?
    
    request.generate_code!
    assert request.generating_code?
    
    request.execute_code!
    assert request.executing?
    
    request.interpret_results!
    assert request.interpreting_results?
    
    request.complete!
    assert request.completed?
  end

  test "should handle failure states" do
    request = create_analysis_request
    request.start_analysis!
    
    request.fail!("Error occurred")
    assert request.failed?
    assert_equal "Error occurred", request.error_message
  end

  test "should calculate estimated completion time based on complexity" do
    request = create_analysis_request(complexity_score: 5.0)
    
    estimated_time = request.estimated_completion_time
    assert estimated_time > Time.current
    assert estimated_time < 3.minutes.from_now
  end

  private

  def build_analysis_request(attributes = {})
    default_attributes = {
      natural_language_query: "What is the average sales by region?",
      user: users(:one),
      dataset: datasets(:one),
      organization: organizations(:one)
    }
    AnalysisRequest.new(default_attributes.merge(attributes))
  end

  def create_analysis_request(attributes = {})
    request = build_analysis_request(attributes)
    request.save!
    request
  end
end