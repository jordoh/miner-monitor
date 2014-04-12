require 'librato/metrics'

class Reporters::Librato
  def initialize(config)
    email, api_key = config.values_at('email', 'api_key')

    raise ArgumentError.new('Librato reporter config requires an email key') unless email
    raise ArgumentError.new('Librato reporter config requires an api_key key') unless api_key

    Librato::Metrics.authenticate email, api_key

    @queue = Librato::Metrics::Queue.new
    @annotator = Librato::Metrics::Annotator.new
  end

  def report_metric(source, name, value)
    @queue.add name => { :source => source, :value => value }
  end

  def report_event(source, name, title, id, time)
    @annotator.add name, title, :source => source, :id => id, :start_time => time.to_i, :end_time => time.to_i
  end

  def finalize
    @queue.submit
  end
end
