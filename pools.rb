module Pools
  def self.klass(pool_name)
    pool_class_name = constants.detect do |pool_class_name|
      pool_class_name.to_s.downcase == pool_name.downcase
    end
    raise ArgumentError.new("Unknown pools '#{ pool_name }'") unless pool_class_name

    const_get(pool_class_name)
  end
end

require_relative 'pools/mpos'