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

    client = CGMiner::API::Client.new(hostname, port || 4028)

    summary = begin
      client.summary.body.first
    rescue Exception => e
      $stderr.puts "Exception reporting cgminer stats for #{ hostname }:#{ port } : #{ e }"
      e.backtrace.to_a.each { |backtrace_line| $stderr.puts backtrace_line }
      return
    end

    [
      [ 'MHS 5s', 'hashrate.5s'],
      [ 'MHS av', 'hashrate.average'],

      [ 'Accepted',     'shares.accepted'],
      [ 'Rejected',     'shares.rejected'],
      [ 'Discarded',    'shares.discarded'],
      [ 'Stale',        'shares.stale'],
      [ 'Work Utility', 'shares.work_utility'],

      [ 'Pool Rejected%', 'pool.reject_rate']
    ].each do |(summary_key, stat_name)|
      api.emit_point("miner.summary.#{ stat_name }", summary[summary_key] || 0, :host => name)
    end

    client.devs.body.each do |device|
      device_name = "gpu#{ device['GPU'] }"

      [
        [ 'Temperature',  'temperature' ],
        [ 'Fan Speed',    'fan.speed' ],
        [ 'Fan Percent',  'fan.percent' ],
        [ 'GPU Activity', 'activity' ],

        [ 'MHS 5s', 'hashrate.5s' ],
        [ 'MHS av', 'hashrate.average' ],

        [ 'Device Hardware%', 'hardware_rate' ],
        [ 'Device Rejected%', 'reject_rate' ],

      ].each do |(device_key, stat_name)|
        api.emit_point("miner.devices.#{ device_name }.#{ stat_name }", device[device_key] || 0, :host => name, :device => device_name)
      end
    end
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