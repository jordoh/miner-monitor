require 'json'
require 'rest_client'

module Pools
  class Mpos
    class ResponseError < StandardError; end

    def initialize(url, user_id, api_key)
      @url, @user_id, @api_key = url, user_id, api_key
    end

    def balance
      data = request :getuserbalance
      data.values_at('confirmed', 'unconfirmed').reduce(0) { |sum, amount| sum + amount }
    end

    def hashrate
      request :getuserhashrate
    end

    def sharerate
      request :getusersharerate
    end

    def workers
      request :getuserworkers
    end

    private

    attr_reader :url, :user_id, :api_key

    def request(action)
      # See https://github.com/MPOS/php-mpos/wiki/API-Reference
      params = {
        :page => 'api',
        :action => action,
        :api_key => api_key,
        :id => user_id,
      }

      response = begin
        RestClient.get url, :params => params
      rescue RestClient::Exception => e
        e.response
      end

      unless response.code == 200
        raise ResponseError.new("#{ action } request failed, got #{ response.code }: #{ response.to_str }")
      end

      begin
        JSON.parse(response)[action.to_s]['data']
      rescue Exception => e
        raise ResponseError.new("Failed to parse #{ action } response: #{ e }")
      end
    end
  end
end