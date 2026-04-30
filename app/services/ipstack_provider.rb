require "json"

class IpstackProvider < GeolocationProvider
  BASE_URL = "https://api.ipstack.com"
  CONNECT_TIMEOUT = 5
  READ_TIMEOUT = 10

  def initialize(access_key:)
    @access_key = access_key
  end

  def lookup(ip)
    connection = Faraday.new(url: BASE_URL) do |f|
      f.options.open_timeout = CONNECT_TIMEOUT
      f.options.timeout = READ_TIMEOUT
    end
    response = connection.get("/#{ip}", access_key: @access_key)
    parse!(response)
  rescue Faraday::TimeoutError, Faraday::ConnectionFailed
    raise ProviderUnavailable
  end

  private

  def parse!(response)
    raise ProviderUnavailable unless response.success?

    response_body = JSON.parse(response.body)

    raise ProviderRateLimited if response_body.dig("error", "code") == 104
    raise ProviderError if response_body["success"] == false

    {
      ip: response_body["ip"],
      ip_type: response_body["type"],
      country_code: response_body["country_code"],
      city: response_body["city"],
      latitude: response_body["latitude"],
      longitude: response_body["longitude"]
    }
  rescue JSON::ParserError
    raise ProviderUnavailable
  end
end
