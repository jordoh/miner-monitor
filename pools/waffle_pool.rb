require 'json'
require 'rest_client'

class Pools::WafflePool
  class ResponseError < StandardError; end

  def initialize(config)
    @address = config['address']
  end

  def stats
    data = request
    balances = data['balances'] || {}
    {
      :hashrate => data['hash_rate'],
      :balance => (balances['confirmed'] || 0) + (balances['unconverted'] || 0)
    }
  end

  private

  attr_reader :address

  def request
    # See http://www.reddit.com/r/wafflepool/comments/1wi8kn/temporary_api/
    response = begin
      RestClient.get 'http://wafflepool.com/tmp_api', :params => { :address => address }
    rescue RestClient::Exception => e
      e.response
    end

    unless response.code == 200
      raise ResponseError.new("Request failed, got #{ response.code }: #{ response.to_str }")
    end

    begin
      JSON.parse(response)
    rescue Exception => e
      raise ResponseError.new("Failed to parse response: #{ e }")
    end
  end
end