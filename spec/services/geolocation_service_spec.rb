require "rails_helper"

RSpec.describe GeolocationService do
  let(:provider) { instance_double(GeolocationProvider) }
  let(:service)  { described_class.new(provider: provider) }

  let(:geo_data) do
    { ip: "8.8.8.8", ip_type: "ipv4", country_code: "US", city: "Mountain View", latitude: 37.386, longitude: -122.0838 }
  end

  before do
    allow(provider).to receive(:lookup).with("8.8.8.8").and_return(geo_data)
  end

  describe "#call" do
    context "new IP" do
      it "creates a Geolocation record and returns :created status" do
        result = service.call("8.8.8.8")
        expect(result[:status]).to eq(:created)
        expect(Geolocation.count).to eq(1)
      end

      it "persists all geo fields returned by the adapter" do
        result = service.call("8.8.8.8")
        geo = result[:geolocation]
        expect(geo.ip.to_s).to eq("8.8.8.8")
        expect(geo.ip_type).to eq("ipv4")
        expect(geo.country_code).to eq("US")
        expect(geo.city).to eq("Mountain View")
        expect(geo.latitude).to eq(37.386)
        expect(geo.longitude).to eq(-122.0838)
      end

      it "stores url_hostname when query was a URL" do
        allow(Resolv).to receive(:getaddress).with("google.com").and_return("8.8.8.8")
        result = service.call("https://google.com")
        expect(result[:geolocation].url_hostname).to eq("google.com")
      end
    end

    context "existing IP" do
      before { service.call("8.8.8.8") }

      it "updates geo fields and returns :ok status" do
        updated_data = geo_data.merge(city: "New York", latitude: 40.71, longitude: -74.00)
        allow(provider).to receive(:lookup).with("8.8.8.8").and_return(updated_data)

        result = service.call("8.8.8.8")
        expect(result[:status]).to eq(:ok)
        expect(result[:geolocation].city).to eq("New York")
      end

      it "does not change id or created_at" do
        original_id         = Geolocation.first.id
        original_created_at = Geolocation.first.created_at

        service.call("8.8.8.8")

        expect(Geolocation.first.id).to eq(original_id)
        expect(Geolocation.first.created_at).to be_within(1.second).of(original_created_at)
      end
    end

    context "concurrent requests for the same IP" do
      it "returns :ok and does not raise when a race condition triggers RecordNotUnique" do
        existing = Geolocation.create!(ip: "8.8.8.8", ip_type: "ipv4", latitude: 37.386, longitude: -122.0838)

        # Simulate the race: find_or_initialize_by returns a new record (not yet persisted),
        # but the INSERT fails because another request already committed the row.
        new_record = Geolocation.new(ip: "8.8.8.8")
        allow(Geolocation).to receive(:find_or_initialize_by).and_return(new_record)
        allow(new_record).to receive(:update!).and_raise(ActiveRecord::RecordNotUnique)

        result = service.call("8.8.8.8")
        expect(result[:status]).to eq(:ok)
        expect(result[:geolocation].id).to eq(existing.id)
      end
    end

    context "adapter errors" do
      it "does not persist a record when adapter raises ProviderUnavailable" do
        allow(provider).to receive(:lookup).and_raise(GeolocationProvider::ProviderUnavailable)
        expect { service.call("8.8.8.8") }.to raise_error(GeolocationProvider::ProviderUnavailable)
        expect(Geolocation.count).to eq(0)
      end

      it "does not persist a record when adapter raises ProviderError" do
        allow(provider).to receive(:lookup).and_raise(GeolocationProvider::ProviderError)
        expect { service.call("8.8.8.8") }.to raise_error(GeolocationProvider::ProviderError)
        expect(Geolocation.count).to eq(0)
      end
    end
  end
end
