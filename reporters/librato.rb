require 'librato'

class Reporters::Librato
  def initialize(config)
    email, api_key = config.values_at('email', 'api_key')

    raise ArgumentError.new('Librato reporter config requires an email key') unless email
    raise ArgumentError.new('Librato reporter config requires an api_key key') unless api_key

    Librato::Metrics.authenticate email, api_key

    @queue = Librato::Metrics::Queue.new
  end

  def report(name, value)
    @queue.add name => value
  end

  def finalize
    @queue.submit
  end
end