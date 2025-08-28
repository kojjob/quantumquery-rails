class TestDataSourceConnectionJob < ApplicationJob
  queue_as :default

  def perform(data_source_connection)
    data_source_connection.connect!
  end
end