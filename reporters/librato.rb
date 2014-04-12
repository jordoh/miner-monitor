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

  def report_event(source, name, title, time)
    timestamp = time.to_i

    event_data = @annotator.fetch name, :sources => [ source ], :start_time => timestamp, :end_time => timestamp
    if event_data && event_data['events'] && event_data['events'][source].is_a?(Array)
      return if event_data['events'][source].any? do |event|
        event['start_time'] == timestamp && event['title'] == title
      end
    end

    @annotator.add name, title, :source => source, :start_time => timestamp, :end_time => timestamp
  end

  def finalize
    @queue.submit
  end
end
