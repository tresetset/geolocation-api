class GeolocationProvider
  class ProviderUnavailable < StandardError; end
  class ProviderRateLimited < StandardError; end
  class ProviderError < StandardError; end

  def lookup(_ip)
    raise NotImplementedError
  end
end
