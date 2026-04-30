class GeolocationProviderFactory
  def self.build
    IpstackProvider.new(access_key: ENV.fetch("IPSTACK_ACCESS_KEY"))
  end
end
