require 'dogapi'

class Reporters::Datadog
  def initialize(config)
    api_key = config['api_key'] or raise ArgumentError.new('datadog api_key is required')

    @api = Dogapi::Client.new(api_key)
  end

  def report_metric(source, name, value)
    @api.emit_point(name, value, :tags => [ source ])
  end

  def report_event(source, name, title, time)
    raise ArgumentError.new('datadog reporter does not support events')
  end

  def finalize
    # Nothing to do here
  end
end