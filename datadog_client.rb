require 'yaml'

require_relative 'pools/mpos'

class DatadogClient
  def initialize(config_path)
    @config = YAML::load(File.read(config_path))
    @datadog_config = @config.delete('datadog')
  end

  def run
    config.each do |metric_name, metric_configs|
      method_name = "report_#{ metric_name }_stats"

      unless private_methods.include?(method_name.to_sym)
        raise ArgumentError.new("Unknown config key '#{ metric_name }'")
      end

      metric_configs = [ metric_configs ] unless metric_configs.is_a?(Array)

      metric_configs.each do |metric_config|
        send method_name, metric_config
      end
    end
  end

  private

  attr_reader :config

  def report_cgminer_stats(cgminer_config)
    name, hostname, port = cgminer_config.values_at('name', 'hostname', 'port')

    raise ArgumentError.new('cgminer.name key is required') unless name
    raise ArgumentError.new('cgminer.hostname key is required') unless hostname

    puts cgminer_config.inspect
  end

  def report_pools_stats(pool_configs)
    pool_configs = [ pool_configs ] unless pool_configs.is_a?(Array)

    pool_configs.each do |pool_config|
      name, type = pool_config.values_at('name', 'type')

      raise ArgumentError.new('pools[n].name key is required') unless name
      raise ArgumentError.new('pools[n].type key is required') unless type

      puts pool_config.inspect
    end
  end
end