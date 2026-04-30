require "rails_helper"

RSpec.describe "POST /api/v1/geolocations", type: :request do
  let(:api_key) { ENV.fetch("API_KEY", "test-api-key") }
  let(:headers) do
    {
      "Content-Type" => "application/vnd.api+json",
      "Accept" => "application/vnd.api+json",
      "X-Api-Key" => api_key
    }
  end

  def post_geolocation(query)
    post "/api/v1/geolocations",
      params: { data: { type: "geolocations", attributes: { query: query } } }.to_json,
      headers: headers
  end

  def json
    response.parsed_body.deep_symbolize_keys
  end

  # ─── Happy path ────────────────────────────────────────────────────────────

  describe "201 Created — bare IPv4", :vcr do
    it "creates a geolocation record and returns JSON:API shape" do
      post_geolocation("8.8.8.8")

      expect(response).to have_http_status(:created)
      expect(response.headers["Location"]).to eq("/api/v1/geolocations/8.8.8.8")
      expect(response.content_type).to include("application/vnd.api+json")

      data  = json[:data]
      attrs = data[:attributes]

      expect(data[:type]).to eq("geolocations")
      expect(data[:id]).to be_present
      expect(data.dig(:links, :self)).to match(%r{/api/v1/geolocations/\S+})

      expect(attrs[:ip]).to eq("8.8.8.8")
      expect(attrs[:url_hostname]).to be_nil
      expect(attrs[:ip_type]).to eq("ipv4")
      expect(attrs[:country_code]).to be_present
      expect(attrs[:city]).to be_present
      expect(attrs[:latitude]).to be_a(Float).and be_between(-90, 90)
      expect(attrs[:longitude]).to be_a(Float).and be_between(-180, 180)
      expect(attrs[:created_at]).to be_present
      expect(attrs[:updated_at]).to be_present

      expect(json[:jsonapi]).to eq({ version: "1.1" })
    end
  end

  describe "201 Created — bare IPv6", :vcr do
    it "creates a geolocation record with ip_type ipv6" do
      post_geolocation("2001:4860:4860::8888")

      expect(response).to have_http_status(:created)

      attrs = json.dig(:data, :attributes)
      expect(attrs[:ip]).to eq("2001:4860:4860::8888")
      expect(attrs[:ip_type]).to eq("ipv6")
      expect(attrs[:url_hostname]).to be_nil
    end
  end

  describe "201 Created — full URL", :vcr do
    before { allow(Resolv).to receive(:getaddress).with("google.com").and_return("142.250.120.100") }

    it "stores hostname (not full URL) in url_hostname and resolves IP" do
      post_geolocation("https://google.com/search?q=hello")

      expect(response).to have_http_status(:created)

      attrs = json.dig(:data, :attributes)
      expect(attrs[:url_hostname]).to eq("google.com")
      expect(attrs[:ip]).to be_present
      expect(attrs[:ip_type]).to be_present
    end
  end

  describe "201 Created — hostname", :vcr do
    before { allow(Resolv).to receive(:getaddress).with("cloudflare.com").and_return("104.16.133.229") }

    it "stores hostname in url_hostname and resolves IP" do
      post_geolocation("cloudflare.com")

      expect(response).to have_http_status(:created)

      attrs = json.dig(:data, :attributes)
      expect(attrs[:url_hostname]).to eq("cloudflare.com")
      expect(attrs[:ip]).to be_present
    end
  end

  describe "200 OK — refresh", vcr: { allow_playback_repeats: true } do
    it "returns 200 with updated geo data on second request for same IP" do
      post_geolocation("8.8.8.8")
      expect(response).to have_http_status(:created)

      first_id         = json.dig(:data, :id)
      first_created_at = json.dig(:data, :attributes, :created_at)

      post_geolocation("8.8.8.8")
      expect(response).to have_http_status(:ok)

      attrs = json.dig(:data, :attributes)
      expect(json.dig(:data, :id)).to eq(first_id)
      expect(attrs[:created_at]).to eq(first_created_at)
      expect(attrs[:updated_at]).to be_present
    end
  end

  # ─── Auth ──────────────────────────────────────────────────────────────────

  describe "401 — missing API key" do
    it "returns unauthorized" do
      post "/api/v1/geolocations",
        params: { data: { type: "geolocations", attributes: { query: "8.8.8.8" } } }.to_json,
        headers: headers.except("X-Api-Key")

      expect(response).to have_http_status(:unauthorized)
      expect(json.dig(:errors, 0, :code)).to eq("unauthorized")
    end
  end

  describe "401 — wrong API key" do
    it "returns unauthorized" do
      post "/api/v1/geolocations",
        params: { data: { type: "geolocations", attributes: { query: "8.8.8.8" } } }.to_json,
        headers: headers.merge("X-Api-Key" => "wrong-key")

      expect(response).to have_http_status(:unauthorized)
      expect(json.dig(:errors, 0, :code)).to eq("unauthorized")
    end
  end

  # ─── Content-Type ──────────────────────────────────────────────────────────

  describe "415 — wrong Content-Type" do
    it "returns unsupported_media_type" do
      post "/api/v1/geolocations",
        params: { data: { type: "geolocations", attributes: { query: "8.8.8.8" } } }.to_json,
        headers: headers.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:unsupported_media_type)
      expect(json.dig(:errors, 0, :code)).to eq("unsupported_media_type")
    end
  end

  # ─── Input validation ──────────────────────────────────────────────────────

  describe "400 — missing query" do
    it "returns missing_parameter" do
      post "/api/v1/geolocations",
        params: { data: { type: "geolocations", attributes: {} } }.to_json,
        headers: headers

      expect(response).to have_http_status(:bad_request)
      expect(json.dig(:errors, 0, :code)).to eq("missing_parameter")
      expect(json.dig(:errors, 0, :source, :pointer)).to eq("/data/attributes/query")
    end
  end

  describe "422 invalid_query" do
    %w[not-an-ip 999.999.999.999 !!!].each do |bad_input|
      it "returns invalid_query for '#{bad_input}'" do
        post_geolocation(bad_input)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.dig(:errors, 0, :code)).to eq("invalid_query")
        expect(json.dig(:errors, 0, :source, :pointer)).to eq("/data/attributes/query")
      end
    end
  end

  describe "422 reserved_ip_address" do
    %w[192.168.1.1 10.0.0.1 127.0.0.1 ::1].each do |private_ip|
      it "returns reserved_ip_address for '#{private_ip}'" do
        post_geolocation(private_ip)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.dig(:errors, 0, :code)).to eq("reserved_ip_address")
        expect(json.dig(:errors, 0, :source, :pointer)).to eq("/data/attributes/query")
      end
    end
  end

  describe "422 unresolvable_host" do
    it "returns unresolvable_host when domain does not resolve" do
      allow_any_instance_of(Resolv::DNS).to receive(:getaddress).and_raise(Resolv::ResolvError)

      post_geolocation("nonexistent.invalid")

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig(:errors, 0, :code)).to eq("unresolvable_host")
      expect(json.dig(:errors, 0, :source, :pointer)).to eq("/data/attributes/query")
    end
  end

  # ─── Provider errors ───────────────────────────────────────────────────────

  describe "503 provider_unavailable — ipstack timeout" do
    it "returns provider_unavailable" do
      stub_request(:get, /api\.ipstack\.com/).to_timeout

      post_geolocation("8.8.8.8")

      expect(response).to have_http_status(:service_unavailable)
      expect(json.dig(:errors, 0, :code)).to eq("provider_unavailable")
    end
  end

  describe "503 provider_unavailable — ipstack 5xx" do
    it "returns provider_unavailable" do
      stub_request(:get, /api\.ipstack\.com/).to_return(status: 500)

      post_geolocation("8.8.8.8")

      expect(response).to have_http_status(:service_unavailable)
      expect(json.dig(:errors, 0, :code)).to eq("provider_unavailable")
    end
  end

  describe "503 provider_rate_limited" do
    it "returns provider_rate_limited" do
      stub_request(:get, /api\.ipstack\.com/)
        .to_return(status: 200, body: { error: { code: 104, info: "monthly limit reached" } }.to_json)

      post_geolocation("8.8.8.8")

      expect(response).to have_http_status(:service_unavailable)
      expect(json.dig(:errors, 0, :code)).to eq("provider_rate_limited")
    end
  end

  describe "502 provider_error — success: false" do
    it "returns provider_error" do
      stub_request(:get, /api\.ipstack\.com/)
        .to_return(status: 200, body: { success: false, error: { code: 101, info: "invalid access key" } }.to_json)

      post_geolocation("8.8.8.8")

      expect(response).to have_http_status(:bad_gateway)
      expect(json.dig(:errors, 0, :code)).to eq("provider_error")
    end
  end

  describe "422 — provider returns null coordinates" do
    it "returns 422 when provider omits latitude/longitude" do
      stub_request(:get, /api\.ipstack\.com/)
        .to_return(status: 200, body: {
          ip: "8.8.8.8", type: "ipv4", country_code: "US",
          city: "Mountain View", latitude: nil, longitude: nil
        }.to_json)

      post_geolocation("8.8.8.8")

      expect(response).to have_http_status(:unprocessable_content)
      expect(json[:errors]).to be_present
    end
  end
end

RSpec.describe "GET /api/v1/geolocations", type: :request do
  let(:api_key) { ENV.fetch("API_KEY", "test-api-key") }
  let(:headers) do
    {
      "Accept" => "application/vnd.api+json",
      "X-Api-Key" => api_key
    }
  end

  def json
    response.parsed_body.deep_symbolize_keys
  end

  describe "200 OK — list" do
    it "returns paginated JSON:API collection with pagination links" do
      Geolocation.create!(ip: "8.8.8.8", ip_type: "ipv4", country_code: "US", latitude: 37.386, longitude: -122.0838)
      Geolocation.create!(ip: "1.1.1.1", ip_type: "ipv4", country_code: "AU", latitude: -33.86, longitude: 151.2)

      get "/api/v1/geolocations", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/vnd.api+json")
      expect(json[:data]).to be_an(Array)
      expect(json[:data].length).to eq(2)
      expect(json.dig(:meta, :page)).to eq(1)
      expect(json.dig(:meta, :per_page)).to be_present
      expect(json.dig(:meta, :total)).to eq(2)
      expect(json[:jsonapi]).to eq({ version: "1.1" })

      links = json[:links]
      expect(links[:first]).to include("page=1")
      expect(links[:last]).to be_present
      expect(links[:next]).to be_nil
      expect(links[:prev]).to be_nil
    end
  end

  describe "200 OK — filter by filter[query]" do
    it "returns matching record as collection" do
      Geolocation.create!(ip: "8.8.8.8", ip_type: "ipv4", country_code: "US", latitude: 37.386, longitude: -122.0838)
      Geolocation.create!(ip: "1.1.1.1", ip_type: "ipv4", country_code: "AU", latitude: -33.86, longitude: 151.2)

      get "/api/v1/geolocations?filter[query]=8.8.8.8", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json[:data].length).to eq(1)
      expect(json.dig(:data, 0, :attributes, :ip)).to eq("8.8.8.8")
      expect(json.dig(:meta, :total)).to eq(1)
      expect(json.dig(:links, :first)).to include("filter")
    end

    it "returns empty collection when no match" do
      get "/api/v1/geolocations?filter[query]=8.8.8.8", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json[:data]).to eq([])
      expect(json.dig(:meta, :total)).to eq(0)
    end
  end

  describe "401 — missing API key" do
    it "returns unauthorized" do
      get "/api/v1/geolocations", headers: headers.except("X-Api-Key")

      expect(response).to have_http_status(:unauthorized)
      expect(json.dig(:errors, 0, :code)).to eq("unauthorized")
    end
  end

  describe "400 — page overflow" do
    it "returns bad request" do
      get "/api/v1/geolocations?page=9999", headers: headers

      expect(response).to have_http_status(:bad_request)
    end
  end
end

RSpec.describe "GET /api/v1/geolocations/:query", type: :request do
  let(:api_key) { ENV.fetch("API_KEY", "test-api-key") }
  let(:headers) do
    {
      "Accept" => "application/vnd.api+json",
      "X-Api-Key" => api_key
    }
  end

  def json
    response.parsed_body.deep_symbolize_keys
  end

  describe "200 OK" do
    let!(:geolocation) do
      Geolocation.create!(
        ip: "8.8.8.8",
        ip_type: "ipv4",
        country_code: "US",
        city: "Mountain View",
        latitude: 37.386,
        longitude: -122.0838
      )
    end

    it "returns geolocation by IP address" do
      get "/api/v1/geolocations/8.8.8.8", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/vnd.api+json")

      data  = json[:data]
      attrs = data[:attributes]

      expect(data[:type]).to eq("geolocations")
      expect(data[:id]).to eq(geolocation.id)
      expect(data.dig(:links, :self)).to match(%r{/api/v1/geolocations/\S+})

      expect(attrs[:ip]).to eq("8.8.8.8")
      expect(attrs[:ip_type]).to eq("ipv4")
      expect(attrs[:country_code]).to eq("US")
      expect(attrs[:city]).to eq("Mountain View")

      expect(json[:jsonapi]).to eq({ version: "1.1" })
    end

    it "returns geolocation by hostname" do
      allow(Resolv).to receive(:getaddress).with("dns.google").and_return("8.8.8.8")

      get "/api/v1/geolocations/dns.google", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json.dig(:data, :attributes, :ip)).to eq("8.8.8.8")
    end
  end

  describe "401 — missing API key" do
    it "returns unauthorized" do
      get "/api/v1/geolocations/8.8.8.8", headers: headers.except("X-Api-Key")

      expect(response).to have_http_status(:unauthorized)
      expect(json.dig(:errors, 0, :code)).to eq("unauthorized")
    end
  end

  describe "404 — not found" do
    it "returns not found for valid IP not in database" do
      get "/api/v1/geolocations/1.2.3.4", headers: headers

      expect(response).to have_http_status(:not_found)
      expect(json.dig(:errors, 0, :code)).to eq("not_found")
    end
  end

  describe "422 — invalid query" do
    it "returns invalid_query for a malformed IP" do
      get "/api/v1/geolocations/not-an-ip", headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json.dig(:errors, 0, :code)).to eq("invalid_query")
    end

    it "returns reserved_ip_address for a private IP" do
      get "/api/v1/geolocations/10.0.0.1", headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json.dig(:errors, 0, :code)).to eq("reserved_ip_address")
    end
  end
end

RSpec.describe "DELETE /api/v1/geolocations/:id", type: :request do
  let(:api_key) { ENV.fetch("API_KEY", "test-api-key") }
  let(:headers) do
    {
      "X-Api-Key" => api_key
    }
  end

  def json
    response.parsed_body.deep_symbolize_keys
  end

  describe "204 No Content" do
    it "deletes by IP address" do
      Geolocation.create!(ip: "1.1.1.1", ip_type: "ipv4", country_code: "AU", latitude: 35.0, longitude: 149.0)

      delete "/api/v1/geolocations/1.1.1.1", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(response.body).to be_empty
      expect(Geolocation.find_by(ip: "1.1.1.1")).to be_nil
    end

    it "deletes by hostname" do
      Geolocation.create!(ip: "1.1.1.1", ip_type: "ipv4", country_code: "AU", latitude: 35.0, longitude: 149.0)
      allow(Resolv).to receive(:getaddress).with("one.one.one.one").and_return("1.1.1.1")

      delete "/api/v1/geolocations/one.one.one.one", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(Geolocation.find_by(ip: "1.1.1.1")).to be_nil
    end
  end

  describe "401 — missing API key" do
    it "returns unauthorized" do
      delete "/api/v1/geolocations/1.1.1.1", headers: {}

      expect(response).to have_http_status(:unauthorized)
      expect(json.dig(:errors, 0, :code)).to eq("unauthorized")
    end
  end

  describe "404 — not found" do
    it "returns not found for valid IP not in database" do
      delete "/api/v1/geolocations/1.2.3.4", headers: headers

      expect(response).to have_http_status(:not_found)
      expect(json.dig(:errors, 0, :code)).to eq("not_found")
    end
  end

  describe "422 — invalid query" do
    it "returns invalid_query for a malformed IP" do
      delete "/api/v1/geolocations/not-an-ip", headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json.dig(:errors, 0, :code)).to eq("invalid_query")
    end

    it "returns reserved_ip_address for a private IP" do
      delete "/api/v1/geolocations/192.168.1.1", headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json.dig(:errors, 0, :code)).to eq("reserved_ip_address")
    end
  end
end

RSpec.describe "IPv6 support in GET and DELETE", type: :request do
  let(:api_key) { ENV.fetch("API_KEY", "test-api-key") }
  let(:headers) { { "Accept" => "application/vnd.api+json", "X-Api-Key" => api_key } }
  let(:ipv6) { "2001:4860:4860::8888" }
  let!(:geolocation) do
    Geolocation.create!(ip: ipv6, ip_type: "ipv6", latitude: 37.386, longitude: -122.0838)
  end

  it "GET returns geolocation by IPv6 address" do
    get "/api/v1/geolocations/#{ipv6}", headers: headers

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("data", "attributes", "ip")).to eq(ipv6)
  end

  it "DELETE removes geolocation by IPv6 address" do
    delete "/api/v1/geolocations/#{ipv6}", headers: headers

    expect(response).to have_http_status(:no_content)
    expect(Geolocation.find_by(ip: ipv6)).to be_nil
  end
end
