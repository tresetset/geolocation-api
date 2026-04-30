require "rails_helper"

RSpec.describe IpstackProvider do
  let(:provider) { described_class.new(access_key: "test_key") }

  describe "#lookup" do
    context "success" do
      it "returns geo data hash with ip, ip_type, country_code, city, latitude, longitude" do
        stub_request(:get, /api\.ipstack\.com/)
          .to_return(
            status: 200,
            body: {
              ip: "8.8.8.8",
              type: "ipv4",
              country_code: "US",
              city: "Mountain View",
              latitude: 37.386,
              longitude: -122.0838
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        result = provider.lookup("8.8.8.8")

        expect(result[:ip]).to eq("8.8.8.8")
        expect(result[:ip_type]).to eq("ipv4")
        expect(result[:country_code]).to eq("US")
        expect(result[:city]).to eq("Mountain View")
        expect(result[:latitude]).to eq(37.386)
        expect(result[:longitude]).to eq(-122.0838)
      end
    end

    context "provider errors" do
      it "raises ProviderRateLimited when error code is 104" do
        stub_request(:get, /api\.ipstack\.com/)
          .to_return(status: 200, body: { error: { code: 104, info: "monthly limit reached" } }.to_json)

        expect { provider.lookup("8.8.8.8") }.to raise_error(GeolocationProvider::ProviderRateLimited)
      end

      it "raises ProviderError when success is false" do
        stub_request(:get, /api\.ipstack\.com/)
          .to_return(status: 200, body: { success: false, error: { code: 101, info: "invalid access key" } }.to_json)

        expect { provider.lookup("8.8.8.8") }.to raise_error(GeolocationProvider::ProviderError)
      end

      it "raises ProviderUnavailable on HTTP 5xx" do
        stub_request(:get, /api\.ipstack\.com/).to_return(status: 500)

        expect { provider.lookup("8.8.8.8") }.to raise_error(GeolocationProvider::ProviderUnavailable)
      end

      it "raises ProviderUnavailable on timeout" do
        stub_request(:get, /api\.ipstack\.com/).to_timeout

        expect { provider.lookup("8.8.8.8") }.to raise_error(GeolocationProvider::ProviderUnavailable)
      end
    end
  end
end
