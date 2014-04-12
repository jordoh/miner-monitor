require 'afstatsd'

class Reporters::AppFirst
  def initialize(config)
    @api = Statsd.new
  end

  def report_metric(source, name, value)
    @api.gauge("#{ source }.#{ name }", value)
  end

  def report_event(source, name, title, time)
    raise ArgumentError.new('appfirst reporter does not support events')
  end

  def finalize
    # Nothing to do here
  end
end