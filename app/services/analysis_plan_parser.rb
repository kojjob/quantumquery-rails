# frozen_string_literal: true

# Service for parsing AI-generated analysis plans from streaming or complete responses
# Handles JSON extraction, validation, error recovery, and plan normalization
class AnalysisPlanParser
  class ParseError < StandardError; end
  class ValidationError < StandardError; end

  # Expected plan structure
  REQUIRED_FIELDS = %w[steps].freeze
  REQUIRED_STEP_FIELDS = %w[type language description].freeze
  
  VALID_STEP_TYPES = %w[
    data_exploration
    statistical_analysis
    visualization
    data_cleaning
    feature_engineering
    model_training
    hypothesis_testing
    correlation_analysis
    time_series_analysis
    clustering
    classification
    regression
  ].freeze

  VALID_LANGUAGES = %w[python r sql].freeze

  attr_reader :raw_text, :plan, :errors, :warnings

  def initialize(raw_text)
    @raw_text = raw_text
    @plan = nil
    @errors = []
    @warnings = []
  end

  # Main parsing entry point
  def parse
    return @plan if @plan # Already parsed

    # Try multiple extraction strategies
    json_text = extract_json_from_text(@raw_text)
    
    if json_text.blank?
      @errors << "No JSON content found in response"
      return nil
    end

    # Parse JSON
    begin
      parsed = JSON.parse(json_text)
    rescue JSON::ParserError => e
      # Try to fix common JSON issues
      json_text = fix_common_json_errors(json_text)
      parsed = JSON.parse(json_text) rescue nil
      
      if parsed.nil?
        @errors << "JSON parsing failed: #{e.message}"
        return nil
      end
      
      @warnings << "JSON required automatic fixing"
    end

    # Normalize and validate structure
    @plan = normalize_plan(parsed)
    
    # Validate happens AFTER normalization to check all required fields
    validate_plan(@plan)

    @plan
  rescue => e
    @errors << "Unexpected parsing error: #{e.message}"
    Rails.logger.error "AnalysisPlanParser error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    nil
  end

  # Check if parsing was successful
  def valid?
    @errors.empty? && @plan.present?
  end

  # Get parsed plan or raise error
  def parse!
    result = parse
    raise ParseError, errors.join("; ") if @errors.any?
    result
  end

  # Extract JSON from markdown code blocks or raw text
  def extract_json_from_text(text)
    return nil if text.blank?

    # Strategy 1: Look for JSON in markdown code blocks
    # ```json ... ``` or ```JSON ... ```
    json_block = text.match(/```(?:json|JSON)\s*\n(.*?)\n```/m)
    return json_block[1].strip if json_block

    # Strategy 2: Look for any code block that contains JSON
    code_block = text.match(/```\s*\n(\{.*?\})\n```/m)
    return code_block[1].strip if code_block

    # Strategy 3: Look for JSON array FIRST (before object)
    json_array = extract_json_array(text)
    return json_array if json_array

    # Strategy 4: Extract JSON object (look for outermost braces)
    json_obj = extract_json_object(text)
    return json_obj if json_obj

    nil
  end

  private

  # Extract JSON object bounded by { }
  def extract_json_object(text)
    start_idx = text.index('{')
    return nil unless start_idx

    # Find matching closing brace
    brace_count = 0
    in_string = false
    escape_next = false
    
    text[start_idx..].each_char.with_index(start_idx) do |char, idx|
      if escape_next
        escape_next = false
        next
      end

      case char
      when '\\'
        escape_next = true if in_string
      when '"'
        in_string = !in_string unless escape_next
      when '{'
        brace_count += 1 unless in_string
      when '}'
        brace_count -= 1 unless in_string
        return text[start_idx..idx] if brace_count.zero?
      end
    end

    nil
  end

  # Extract JSON array bounded by [ ]
  def extract_json_array(text)
    start_idx = text.index('[')
    return nil unless start_idx

    bracket_count = 0
    in_string = false
    escape_next = false
    
    text[start_idx..].each_char.with_index(start_idx) do |char, idx|
      if escape_next
        escape_next = false
        next
      end

      case char
      when '\\'
        escape_next = true if in_string
      when '"'
        in_string = !in_string
      when '['
        bracket_count += 1 unless in_string
      when ']'
        bracket_count -= 1 unless in_string
        return text[start_idx..idx] if bracket_count.zero?
      end
    end

    nil
  end

  # Fix common JSON formatting errors
  def fix_common_json_errors(json_text)
    fixed = json_text.dup

    # Remove trailing commas before ] or }
    fixed.gsub!(/,(\s*[\]}])/, '\1')

    # Fix single quotes (should be double quotes in JSON)
    # Be careful not to replace quotes inside strings
    fixed.gsub!(/(\w)'(\w)/, '\1"\2') # Property names
    
    # Remove comments (// or /* */)
    fixed.gsub!(%r{//.*$}, '') # Single-line comments
    fixed.gsub!(%r{/\*.*?\*/}m, '') # Multi-line comments

    # Ensure proper string quoting for unquoted property names
    fixed.gsub!(/(\w+)(\s*:\s*)/, '"\1"\2')

    # Remove control characters
    fixed.gsub!(/[\x00-\x1F\x7F]/, '')

    fixed
  end

  # Normalize plan structure to expected format
  def normalize_plan(parsed)
    normalized = {}

    # Handle different response formats
    if parsed.is_a?(Array)
      # If we got an array of steps directly
      normalized["steps"] = parsed
    elsif parsed.is_a?(Hash)
      if parsed["steps"]
        normalized["steps"] = parsed["steps"]
        # Preserve metadata from root
        normalized["metadata"] = parsed["metadata"] unless parsed["metadata"].nil?
        normalized["reasoning"] = parsed["reasoning"] unless parsed["reasoning"].nil?
      elsif parsed["analysis_plan"]
        plan = parsed["analysis_plan"]
        if plan.is_a?(Hash)
          normalized["steps"] = plan["steps"] || [plan]
          # Preserve metadata from analysis_plan
          normalized["metadata"] = plan["metadata"] unless plan["metadata"].nil?
          normalized["reasoning"] = plan["reasoning"] unless plan["reasoning"].nil?
        elsif plan.is_a?(Array)
          normalized["steps"] = plan
        end
      elsif parsed["plan"]
        plan = parsed["plan"]
        if plan.is_a?(Hash)
          normalized["steps"] = plan["steps"] || [plan]
        elsif plan.is_a?(Array)
          normalized["steps"] = plan
        end
      else
        # Assume the hash itself is a single step
        normalized["steps"] = [parsed]
      end
    else
      raise ValidationError, "Unexpected plan format: #{parsed.class}"
    end

    # Normalize each step
    normalized["steps"] = normalized["steps"].map.with_index do |step, idx|
      normalize_step(step, idx)
    end

    normalized
  end

  # Normalize individual step structure
  def normalize_step(step, index)
    return step if step.blank?

    normalized = {
      "sequence_number" => index
    }
    
    # Only set fields if they exist (to allow validation to catch missing required fields)
    normalized["type"] = infer_step_type(step) if step["type"] || step["step_type"] || step["kind"] || step["action"]
    normalized["language"] = infer_language(step) if step["language"] || step["lang"] || step["code_language"]
    normalized["description"] = infer_description(step) if step["description"] || step["desc"] || step["summary"] || step["name"]

    # Preserve optional fields
    normalized["dependencies"] = step["dependencies"] if step["dependencies"]
    normalized["timeout"] = step["timeout"]&.to_i if step["timeout"]
    normalized["code_template"] = step["code_template"] if step["code_template"]
    normalized["expected_output"] = step["expected_output"] if step["expected_output"]

    normalized
  end

  # Infer step type from various field names
  def infer_step_type(step)
    step["type"] || 
    step["step_type"] || 
    step["kind"] || 
    step["action"] || 
    "data_exploration" # Default
  end

  # Infer language from various field names
  def infer_language(step)
    language = step["language"] || 
               step["lang"] || 
               step["code_language"] ||
               "python" # Default

    language.downcase
  end

  # Infer description from various field names
  def infer_description(step)
    step["description"] || 
    step["desc"] || 
    step["summary"] || 
    step["name"] ||
    "Analysis step"
  end

  # Validate plan structure and content
  def validate_plan(plan)
    return unless plan

    # Check required fields
    REQUIRED_FIELDS.each do |field|
      unless plan.key?(field)
        @errors << "Missing required field: #{field}"
      end
    end

    return unless plan["steps"]

    # Check steps is an array
    unless plan["steps"].is_a?(Array)
      @errors << "Field 'steps' must be an array"
      return
    end

    # Check for empty steps
    if plan["steps"].empty?
      @errors << "Plan must contain at least one step"
    end

    # Validate each step
    plan["steps"].each_with_index do |step, idx|
      validate_step(step, idx)
    end

    # Check for duplicate sequence numbers
    sequences = plan["steps"].map { |s| s["sequence_number"] }.compact
    if sequences.uniq.length != sequences.length
      @errors << "Duplicate sequence numbers detected"
    end
  end

  # Validate individual step
  def validate_step(step, index)
    step_label = "Step #{index + 1}"

    unless step.is_a?(Hash)
      @errors << "#{step_label}: Must be a hash/object"
      return
    end

    # Check required fields
    REQUIRED_STEP_FIELDS.each do |field|
      value = step[field]
      if value.nil? || (value.respond_to?(:empty?) && value.empty?)
        @errors << "#{step_label}: Missing required field '#{field}'"
      end
    end

    # Validate step type
    if step["type"].present? && !VALID_STEP_TYPES.include?(step["type"])
      @warnings << "#{step_label}: Unknown step type '#{step["type"]}' (will be accepted anyway)"
    end

    # Validate language
    if step["language"].present?
      lang = step["language"].downcase
      unless VALID_LANGUAGES.include?(lang)
        @errors << "#{step_label}: Unsupported language '#{step["language"]}'"
      end
    end

    # Validate description length
    if step["description"].present? && step["description"].length > 500
      @warnings << "#{step_label}: Description is very long (#{step["description"].length} chars)"
    end

    # Validate dependencies reference valid steps
    if step["dependencies"].is_a?(Array)
      step["dependencies"].each do |dep|
        unless dep.is_a?(Integer) && dep >= 0 && dep < index
          @errors << "#{step_label}: Invalid dependency reference: #{dep}"
        end
      end
    end
  end
end
