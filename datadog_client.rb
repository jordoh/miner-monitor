require 'cgminer/api'
require 'cryptsy/api'
require 'dogapi'
require 'yaml'

require_relative 'pools'

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

  def report_miners_stats(api, miner_config)
    name, hostname = required_config_values('miners', miner_config, 'name', 'hostname')

    client = CGMiner::API::Client.new(hostname, miner_config['port'] || 4028)

    summary = without_exceptions do
      client.summary.body.first
    end
    return unless summary

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

  def report_pools_stats(api, pool_config)
    pool_name, pool_type = required_config_values('pools', pool_config, 'name', 'type')

    pool_stats = Pools.klass(pool_type).new(pool_config).stats
    pool_stats.each do |stat_name, stat_value|
      api.emit_point("pool.#{ pool_name.to_s.gsub(/\W/, '_') }.#{ stat_name }".downcase, stat_value)
    end
  end

  def report_exchange_rates_stats(api, exchange_rate_config)
    pair = required_config_values('exchange_rates', exchange_rate_config, 'pair').first

    exchange_client = Cryptsy::API::Client.new

    markets_data = without_exceptions do
      exchange_client.marketdata['return']['markets']
    end
    return unless markets_data

    market_data = markets_data[pair]
    raise ArgumentError.new("Unknown exchange pair #{ pair }") unless market_data

    last_price = market_data['lasttradeprice'].to_f
    if last_price > 0
      api.emit_point("exchange.cryptsy.#{ pair.downcase.gsub(/\W/, '_') }", last_price)
    end
  end

  def required_config_values(category, category_config, *keys)
    values = category_config.values_at(*keys)

    values.each_with_index do |value, index|
      raise ArgumentError.new("#{ category }[n].#{ keys[index] } key is required") unless value
    end

    values
  end

  def without_exceptions
    begin
      yield
    rescue Exception => e
      $stderr.puts e.to_s
      e.backtrace.to_a.each { |backtrace_line| $stderr.puts backtrace_line }
      nil
    end
  end
end