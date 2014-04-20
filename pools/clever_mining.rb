require 'json'
require 'nokogiri'
require 'rest_client'
require 'time'

class Pools::CleverMining
  USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/33.0.1750.152 Safari/537.36'

  class ResponseError < StandardError; end

  def initialize(config)
    @address = config['address']

    raise ArgumentError.new('CleverMining pool config requires an address key') unless address
  end

  def stats
    data = {}

    portlets do |title, body|
      case title
        when /current balances/i
          # This is the "Ready For Payout" amount, not the "Total Expected"
          data[:balance] = body.css('table tr:eq(3) td span.label-success').text.to_f
        when /last hour hashrate/i
          data[:last_24h_hashrate] = body.css('.easy-pie-chart span:first').text.to_f
        when /statistics and info/i
          data[:last_24h_profit] = body.css('table tr:eq(2) td').text.to_f
        when /accepted mh\/s\s*\Z/i
          chart_data = JSON.parse(body.css('.chart').attr('data-series').to_s).first['data']
          data[:hashrate] = chart_data.last.last.to_f
      end
    end

    {
      :balance => data[:balance],
      :hashrate => data[:hashrate],
      :payout_per_day => data[:last_24h_profit],
      :payout_per_day_per_mh => data[:last_24h_profit] / data[:last_24h_hashrate]
    }
  end

  def events
    payout_portlet = portlets.detect { |title, body| title =~ /\A\s*payouts\s*\Z/i }.last

    payout_portlet.css('table > tbody > tr').map do |payout_row|
      time, amount, transaction_id = payout_row.css('td').map { |element| element.text }
      {
        :name => 'payout',
        :time => Time.parse("#{ time } UTC").localtime,
        :title => "#{ amount } sent to #{ address } (#{ transaction_id })"
      }
    end
  end

  private

  attr_reader :address

  def portlets
    return to_enum(:portlets) unless block_given?

    request.css('.page-content .portlet').each do |portlet|
      title = portlet.css('.portlet-title .caption').text
      body = portlet.css('.portlet-body')

      yield title, body
    end
  end

  def request
    @document ||= begin
      domain = 'www.clevermining.com'
      url = "http://#{ domain }/users/#{ address }"
      headers = { :user_agent => USER_AGENT }

      response = begin
        RestClient.get url, headers
      rescue RestClient::Exception => e
        e.response
      end

      if response.code == 503 && response.body.include?('DDoS protection by CloudFlare')
        # The initial response from CloudFlare is a 503 with a challenge in javascript
        begin
          document = Nokogiri::HTML(response)

          # Answer the challenge
          verification_code = document.xpath(".//input[@name='jschl_vc']").attr('value').value
          arithmetic = document.xpath('.//script').last.text.scan(/a\.value\s*=\s*([\d\*\+\-\\]+)\s*;/).flatten.first
          answer = eval(arithmetic) + domain.size
          headers[:params] = { :jschl_vc => verification_code, :jschl_answer => answer }

          # Must include the referer, or CloudFlare will redirect to the root path
          headers[:referer] = url

          # The 503 response returns a '__cfuid' cookie, which (probably) needs to be included in the next request
          headers[:cookies] = response.cookies

          # This will result in a 302 - assuming the answer to the challenge is correct - that sets a 'cf_clearance'
          # cookie, which can be used to access the final page (following the redirect).
          response = RestClient.get("http://#{ domain }/cdn-cgi/l/chk_jschl", headers)
        rescue Exception => e
          raise ResponseError.new("Error bypassing CloudFlare protection: #{ e }")
        end
      end

      unless response.code == 200
        raise ResponseError.new("Request failed, got #{ response.code }: #{ response.to_str }")
      end

      begin
        Nokogiri::HTML(response)
      rescue Exception => e
        raise ResponseError.new("Failed to parse #{ action } response: #{ e }")
      end
    end
  end
end
