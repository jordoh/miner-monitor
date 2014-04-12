require 'afstatsd'

class Reporters::AppFirst
  def initialize(config)
    @api = Statsd.new
  end

  def report(source, name, value)
    @api.gauge("#{ source }.#{ name }", value)
  end

  def finalize
    # Nothing to do here
  end
end