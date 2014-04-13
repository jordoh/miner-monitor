require 'cgminer/api'
require 'cryptsy/api'
require 'yaml'

require_relative 'pools'
require_relative 'reporters'

class MinerMonitor
  def initialize(config_path)
    @config = YAML::load(File.read(config_path))
  end

  def run
    reporter_config = @config.delete('reporter') or raise ArgumentError.new('No reporter configured')
    reporter_type, reporter_config = reporter_config.values_at('type', 'config')
    raise ArgumentError.new('reporter.type is required') unless reporter_type

    reporter = Reporters.klass(reporter_type).new(reporter_config || {})

    config.each do |metric_name, metric_configs|
      method_name = "report_#{ metric_name }_stats"

      unless private_methods.include?(method_name.to_sym)
        raise ArgumentError.new("Unknown config key '#{ metric_name }'")
      end

      metric_configs = [ metric_configs ] unless metric_configs.is_a?(Array)

      metric_configs.each do |metric_config|
        send method_name, reporter, metric_config
      end
    end

    reporter.finalize
  end

  private

  attr_reader :config

  def report_miners_stats(reporter, miner_config)
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
      reporter.report_metric(name, "miner.summary.#{ stat_name }", summary[summary_key] || 0)
    end

    client.devs.body.each do |device|
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
        reporter.report_metric("#{ name }.gpu#{ device['GPU'] }", "miner.devices.#{ stat_name }", device[device_key] || 0)
      end
    end
  end

  def report_pools_stats(reporter, pool_config)
    pool_name, pool_type = required_config_values('pools', pool_config, 'name', 'type')

    pool_client = Pools.klass(pool_type).new(pool_config)

    pool_stats = pool_client.stats
    pool_stats.each do |stat_name, stat_value|
      reporter.report_metric(pool_name, "pool.#{ stat_name }".downcase, stat_value)
    end

    if pool_client.respond_to?(:events)
      without_exceptions do
        pool_client.events.each do |event|
          event_name, event_time, event_title = event.values_at(:name, :time, :title)
          reporter.report_event(pool_name, event_name, event_title, event_time)
        end
      end
    end
  end

  def report_exchange_rates_stats(reporter, exchange_rate_config)
    pair = required_config_values('exchange_rates', exchange_rate_config, 'pair').first

    exchange_name = 'cryptsy'
    exchange_client = Cryptsy::API::Client.new

    markets_data = without_exceptions do
      exchange_client.marketdata['return']['markets']
    end
    return unless markets_data

    market_data = markets_data[pair]
    raise ArgumentError.new("Unknown exchange pair #{ pair }") unless market_data

    last_price = market_data['lasttradeprice'].to_f
    if last_price > 0
      reporter.report_metric(exchange_name, "exchange.#{ pair.downcase.gsub(/\W/, '_') }", last_price)
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