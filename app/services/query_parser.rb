require "resolv"
require "uri"
require "ipaddr"

class QueryParser
  class InvalidQuery < StandardError; end
  class ReservedIpAddress < StandardError; end
  class UnresolvableHost < StandardError; end

  RESERVED_RANGES = [
    IPAddr.new("10.0.0.0/8"),
    IPAddr.new("172.16.0.0/12"),
    IPAddr.new("192.168.0.0/16"),
    IPAddr.new("127.0.0.0/8"),
    IPAddr.new("169.254.0.0/16"),
    IPAddr.new("::1/128"),
    IPAddr.new("fc00::/7"),
    IPAddr.new("fe80::/10")
  ].freeze

  IP_PATTERN = /\A[\d.:a-fA-F]+\z/
  HOSTNAME_PATTERN = /\A[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?)+\z/

  def initialize(query)
    @query = query.to_s.strip
  end

  def parse
    if @query.match?(IP_PATTERN)
      parse_as_ip
    elsif url?
      parse_as_url
    elsif @query.match?(HOSTNAME_PATTERN)
      parse_as_hostname(@query, url_hostname: @query)
    else
      raise InvalidQuery
    end
  end

  private

  def parse_as_ip
    addr = IPAddr.new(@query)
    validate_not_reserved!(addr)
    { ip: @query, url_hostname: nil }
  rescue IPAddr::InvalidAddressError
    raise InvalidQuery
  end

  def parse_as_url
    host = URI.parse(@query).host
    raise InvalidQuery if host.blank?

    parse_as_hostname(host, url_hostname: host)
  rescue URI::InvalidURIError
    raise InvalidQuery
  end

  def parse_as_hostname(hostname, url_hostname:)
    ip_str = Resolv.getaddress(hostname)
    validate_not_reserved!(IPAddr.new(ip_str))
    { ip: ip_str, url_hostname: url_hostname }
  rescue Resolv::ResolvError
    raise UnresolvableHost
  end

  def url?
    uri = URI.parse(@query)
    uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end

  def validate_not_reserved!(addr)
    raise ReservedIpAddress if RESERVED_RANGES.any? { |range| range.include?(addr) }
  end
end
