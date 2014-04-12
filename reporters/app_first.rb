require 'afstatsd'

class Reporters::AppFirst
  def initialize(config)
    @api = Statsd.new
  end

  def report(name, value)
    @api.gauge(name, value)
  end

  def finalize
    # Nothing to do here
  end
end