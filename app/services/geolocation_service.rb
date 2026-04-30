class GeolocationService
  def initialize(provider:)
    @provider = provider
  end

  def call(query)
    parsed_query = QueryParser.new(query).parse
    geo_data = @provider.lookup(parsed_query[:ip])

    attrs = {
      url_hostname: parsed_query[:url_hostname],
      ip_type: geo_data[:ip_type],
      country_code: geo_data[:country_code],
      city: geo_data[:city],
      latitude: geo_data[:latitude],
      longitude: geo_data[:longitude]
    }

    Geolocation.transaction do
      geolocation = Geolocation.find_or_initialize_by(ip: parsed_query[:ip])
      status = geolocation.new_record? ? :created : :ok
      geolocation.update!(attrs)
      { geolocation: geolocation, status: status }
    rescue ActiveRecord::RecordNotUnique
      geolocation = Geolocation.find_by!(ip: parsed_query[:ip])
      geolocation.update!(attrs)
      { geolocation: geolocation, status: :ok }
    end
  end
end
