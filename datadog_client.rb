require 'cgminer/api'
require 'dogapi'
require 'yaml'

require_relative 'pools/mpos'

class DatadogClient
  def initialize(config_path)
    @config = YAML::load(File.read(config_path))
    @datadog_config = @config.delete('datadog')
  end

  def run
    api = Dogapi::Client.new(datadog_config['api_key'])

    config.each do |metric_name, metric_configs|
      method_name = "report_#{ metric_name }_stats"

      unless private_methods.include?(method_name.to_sym)
        raise ArgumentError.new("Unknown config key '#{ metric_name }'")
      end

      metric_configs = [ metric_configs ] unless metric_configs.is_a?(Array)

      metric_configs.each do |metric_config|
        send method_name, api, metric_config
      end
    end
  end

  private

  attr_reader :config, :datadog_config

  def report_cgminer_stats(api, cgminer_config)
    name, hostname, port = cgminer_config.values_at('name', 'hostname', 'port')

    raise ArgumentError.new('cgminer.name key is required') unless name
    raise ArgumentError.new('cgminer.hostname key is required') unless hostname

    puts cgminer_config.inspect
  end

  def report_pools_stats(api, pool_configs)
    pool_configs = [ pool_configs ] unless pool_configs.is_a?(Array)

    pool_configs.each do |pool_config|
      pool_name, pool_type = pool_config.values_at('name', 'type')

      raise ArgumentError.new('pools[n].name key is required') unless pool_name
      raise ArgumentError.new('pools[n].type key is required') unless pool_type

      pool_class_name = Pools.constants.detect do |pool_class_name|
        pool_class_name.to_s.downcase == pool_type.downcase
      end
      raise ArgumentError.new("Unknown pools[n].type key: #{ pool_type }") unless pool_class_name

      pool_class = Pools.const_get(pool_class_name)

      pool_stats = pool_class.new(pool_config).stats

      pool_stats.each do |stat_name, stat_value|
        api.emit_point("pools.#{ pool_name.to_s.gsub(/\W/, '_') }.#{ stat_name }".downcase, stat_value)
      end
    end
  end
end