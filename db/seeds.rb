geolocations = [
  {
    ip: "8.8.8.8",
    url_hostname: nil,
    ip_type: "ipv4",
    country_code: "US",
    city: "Mountain View",
    latitude: 37.386051,
    longitude: -122.083855
  },
  {
    ip: "1.1.1.1",
    url_hostname: nil,
    ip_type: "ipv4",
    country_code: "AU",
    city: "Research",
    latitude: -37.7,
    longitude: 145.1833
  },
  {
    ip: "185.93.1.1",
    url_hostname: "github.com",
    ip_type: "ipv4",
    country_code: "DE",
    city: "Frankfurt am Main",
    latitude: 50.1188,
    longitude: 8.6843
  },
  {
    ip: "2606:4700:4700::1111",
    url_hostname: nil,
    ip_type: "ipv6",
    country_code: "US",
    city: "San Jose",
    latitude: 37.3382,
    longitude: -121.8863
  }
]

geolocations.each do |attrs|
  Geolocation.find_or_create_by!(ip: attrs[:ip]) do |geo|
    geo.assign_attributes(attrs)
  end
end

puts "Seeded #{geolocations.size} geolocations."
