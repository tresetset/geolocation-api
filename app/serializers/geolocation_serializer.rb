class GeolocationSerializer
  include JSONAPI::Serializer

  set_type :geolocations

  attribute :ip do |geo|
    geo.ip.to_s
  end

  attributes :url_hostname, :ip_type, :country_code, :city, :created_at, :updated_at

  attribute :latitude do |geo|
    geo.latitude.to_f.round(6)
  end

  attribute :longitude do |geo|
    geo.longitude.to_f.round(6)
  end

  link :self do |geo|
    "/api/v1/geolocations/#{geo.ip}"
  end
end
