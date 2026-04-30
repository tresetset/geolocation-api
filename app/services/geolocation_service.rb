class GeolocationService
  def initialize(provider:)
    @provider = provider
  end

  def call(query)
    parsed_query = QueryParser.new(query).parse
    geo_data = @provider.lookup(parsed_query[:ip])

    Geolocation.transaction do
      geolocation = Geolocation.find_or_initialize_by(ip: parsed_query[:ip])
      status = geolocation.new_record? ? :created : :ok

      geolocation.update!(
        url_hostname: parsed_query[:url_hostname],
        ip_type: geo_data[:ip_type],
        country_code: geo_data[:country_code],
        city: geo_data[:city],
        latitude: geo_data[:latitude],
        longitude: geo_data[:longitude]
      )

      { geolocation: geolocation, status: status }
    end
  end
end
