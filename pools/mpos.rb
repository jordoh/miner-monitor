require 'json'
require 'rest_client'

module Pools
  class Mpos
    class ResponseError < StandardError; end

    def initialize(config)
      @url, @user_id, @api_key = config.values_at('url', 'user_id', 'api_key')

      raise ArgumentError.new('MPos pool config requires a url key') unless url
      raise ArgumentError.new('MPos pool config requires a user_id key') unless user_id
      raise ArgumentError.new('MPos pool config requires an api_key key') unless api_key
    end

    def stats
      {
        :balance => balance,
        :hashrate => hashrate
      }
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