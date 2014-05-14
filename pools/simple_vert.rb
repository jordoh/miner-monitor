require 'json'
require 'rest_client'
require 'time'

class Pools::SimpleVert
  def initialize(config)
    @address = config['address']
  end

  def stats
    data = request

    result = {
      :hashrate => data['last_10_hashrate'].to_f
    }

    if (payout_per_day = data['daily_est'].to_f) > 0
      result[:payout_per_day] = payout_per_day
      result[:payout_per_day_per_mh] = payout_per_day / result[:hashrate] if result[:hashrate] > 0
    end

    result
  end

  private

  attr_reader :address

  def request
    @request ||= begin
      response = begin
        RestClient.get "http://www.simplevert.com/api/#{ address }"
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
end