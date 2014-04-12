module Reporters
  def self.klass(reporter_name)
    class_name = constants.detect do |class_name|
      class_name.to_s.downcase == reporter_name.downcase
    end
    raise ArgumentError.new("Unknown reporter '#{ reporter_name }'") unless class_name

    const_get(class_name)
  end
end

require_relative 'reporters/app_first'
require_relative 'reporters/datadog'
require_relative 'reporters/librato'