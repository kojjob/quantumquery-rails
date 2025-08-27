module AnalysisRequestsHelper
  def step_icon(step)
    case step.status.to_sym
    when :pending
      content_tag :div, class: "h-8 w-8 rounded-full bg-gray-200 flex items-center justify-center" do
        content_tag :svg, class: "h-5 w-5 text-gray-500", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24" do
          tag :path, "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2",
              d: "M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
        end
      end
    when :validating, :executing
      content_tag :div, class: "h-8 w-8 rounded-full bg-blue-100 flex items-center justify-center" do
        content_tag :svg, class: "animate-spin h-5 w-5 text-blue-600", fill: "none", viewBox: "0 0 24 24" do
          concat(tag :circle, class: "opacity-25", cx: "12", cy: "12", r: "10", stroke: "currentColor", "stroke-width": "4")
          concat(tag :path, class: "opacity-75", fill: "currentColor", d: "M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z")
        end
      end
    when :completed
      content_tag :div, class: "h-8 w-8 rounded-full bg-green-100 flex items-center justify-center" do
        content_tag :svg, class: "h-5 w-5 text-green-600", fill: "currentColor", viewBox: "0 0 20 20" do
          tag :path, "fill-rule": "evenodd",
              d: "M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z",
              "clip-rule": "evenodd"
        end
      end
    when :failed
      content_tag :div, class: "h-8 w-8 rounded-full bg-red-100 flex items-center justify-center" do
        content_tag :svg, class: "h-5 w-5 text-red-600", fill: "currentColor", viewBox: "0 0 20 20" do
          tag :path, "fill-rule": "evenodd",
              d: "M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z",
              "clip-rule": "evenodd"
        end
      end
    else
      content_tag :div, class: "h-8 w-8 rounded-full bg-gray-200 flex items-center justify-center" do
        content_tag :span, "", class: "h-2 w-2 bg-gray-400 rounded-full"
      end
    end
  end
  
  def step_border_color(step)
    case step.status.to_sym
    when :completed
      "border-green-200 bg-green-50"
    when :failed
      "border-red-200 bg-red-50"
    when :executing, :validating
      "border-blue-200 bg-blue-50"
    else
      "border-gray-200"
    end
  end
  
  def format_execution_time(milliseconds)
    return "-" unless milliseconds
    
    seconds = milliseconds / 1000.0
    if seconds < 1
      "#{milliseconds}ms"
    elsif seconds < 60
      "#{number_with_precision(seconds, precision: 1)}s"
    else
      minutes = seconds / 60
      "#{number_with_precision(minutes, precision: 1)}m"
    end
  end
  
  def analysis_type_icon(type)
    case type.to_s
    when 'exploratory'
      "🔍"
    when 'statistical'
      "📊"
    when 'predictive'
      "🎯"
    when 'descriptive'
      "📝"
    when 'diagnostic'
      "🔬"
    else
      "📈"
    end
  end
  
  def format_code(code, language)
    # In production, you'd use a syntax highlighter like Rouge
    content_tag :pre, class: "bg-gray-900 text-gray-100 p-4 rounded-lg overflow-x-auto" do
      content_tag :code, code, class: "language-#{language}"
    end
  end
end