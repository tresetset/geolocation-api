class Geolocation < ApplicationRecord
  validates :ip, presence: true, uniqueness: true
  validates :ip_type, presence: true, inclusion: { in: %w[ipv4 ipv6] }
  validates :country_code, length: { maximum: 2 }, allow_nil: true
  validates :latitude, presence: true, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }
  validates :longitude, presence: true, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }

  validate :ip_must_be_valid_inet

  def self.for_query(query)
    where(ip: QueryParser.new(query).parse[:ip])
  rescue QueryParser::InvalidQuery, QueryParser::ReservedIpAddress, QueryParser::UnresolvableHost
    none
  end

  private

  def ip_must_be_valid_inet
    return if ip.blank?

    IPAddr.new(ip.to_s)
  rescue IPAddr::InvalidAddressError
    errors.add(:ip, :invalid)
  end
end
