require 'json'
require 'rest_client'

class Pools::Mpos
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
      :hashrate => hashrate,
      :difficulty => difficulty,
      :payout_per_day => payout_per_day
    }
  end

  def events
    data = request :getusertransactions
    transactions = data['transactions']

    transactions.keep_if do |transaction|
      transaction['type'] == 'Debit_AP'
    end

    transactions.map do |transaction|
      {
        :name => 'payout',
        :time => Time.parse("#{ transaction['timestamp'] } UTC").localtime,
        :title => "#{ transaction['amount' ]} sent to #{ transaction['coin_address'] } (#{ transaction['txid'] })"
      }
    end
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

  def difficulty
    request :getdifficulty
  end

  def workers
    request :getuserworkers
  end

  def payout_per_day
    data = request :getusertransactions
    transactions = data['transactions']
    return nil unless transactions.size > 1

    total_payout = transactions.reduce(0) do |sum, transaction|
      type, confirmations = transaction.values_at('type', 'confirmations')

      # A -1 confirmation value indicates an orphaned block (no payout)

      sum + (type == 'Credit' && confirmations.to_i != -1  ? transaction['amount'] : 0)
    end

    seconds_elapsed = Time.parse(transactions.first['timestamp']) - Time.parse(transactions.last['timestamp'])
    days_elapsed = seconds_elapsed / 86_400

    total_payout / days_elapsed
  end

  private

  attr_reader :url, :user_id, :api_key

  def request(action)
    @cached_data ||= {}
    return @cached_data[action].dup if @cached_data.has_key?(action)

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