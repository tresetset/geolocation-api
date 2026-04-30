require "rails_helper"

RSpec.describe Geolocation, type: :model do
  def valid_attrs(overrides = {})
    { ip: "8.8.8.8", ip_type: "ipv4", latitude: 37.386, longitude: -122.0838 }.merge(overrides)
  end

  describe "validations" do
    it "is valid with valid attributes" do
      expect(Geolocation.new(valid_attrs)).to be_valid
    end

    it "is invalid without ip" do
      expect(Geolocation.new(valid_attrs(ip: nil))).not_to be_valid
    end

    it "is invalid with duplicate ip" do
      Geolocation.create!(valid_attrs)
      expect(Geolocation.new(valid_attrs)).not_to be_valid
    end

    it "is invalid with malformed ip" do
      expect(Geolocation.new(valid_attrs(ip: "999.999.999.999"))).not_to be_valid
    end

    it "is invalid with ip_type other than ipv4 or ipv6" do
      expect(Geolocation.new(valid_attrs(ip_type: "unknown"))).not_to be_valid
    end

    it "is invalid without ip_type" do
      expect(Geolocation.new(valid_attrs(ip_type: nil))).not_to be_valid
    end

    it "is invalid without latitude" do
      expect(Geolocation.new(valid_attrs(latitude: nil))).not_to be_valid
    end

    it "is invalid when latitude is out of range" do
      expect(Geolocation.new(valid_attrs(latitude: 90.000001))).not_to be_valid
      expect(Geolocation.new(valid_attrs(latitude: -90.000001))).not_to be_valid
    end

    it "is valid at latitude boundaries" do
      expect(Geolocation.new(valid_attrs(latitude: 90))).to be_valid
      expect(Geolocation.new(valid_attrs(latitude: -90))).to be_valid
    end

    it "is invalid without longitude" do
      expect(Geolocation.new(valid_attrs(longitude: nil))).not_to be_valid
    end

    it "is invalid when longitude is out of range" do
      expect(Geolocation.new(valid_attrs(longitude: 180.000001))).not_to be_valid
      expect(Geolocation.new(valid_attrs(longitude: -180.000001))).not_to be_valid
    end

    it "is valid at longitude boundaries" do
      expect(Geolocation.new(valid_attrs(longitude: 180))).to be_valid
      expect(Geolocation.new(valid_attrs(longitude: -180))).to be_valid
    end

    it "is valid when country_code and city are nil" do
      expect(Geolocation.new(valid_attrs(country_code: nil, city: nil))).to be_valid
    end

    it "is invalid when country_code exceeds 2 characters" do
      expect(Geolocation.new(valid_attrs(country_code: "USA"))).not_to be_valid
    end
  end

  describe ".for_query" do
    let!(:geo) { Geolocation.create!(valid_attrs(ip: "8.8.8.8")) }

    it "returns matching record for a valid IP" do
      expect(Geolocation.for_query("8.8.8.8")).to contain_exactly(geo)
    end

    it "returns none for an invalid query" do
      expect(Geolocation.for_query("not-an-ip")).to be_empty
    end

    it "returns none for a reserved IP" do
      expect(Geolocation.for_query("192.168.1.1")).to be_empty
    end

    it "returns none for an unresolvable hostname" do
      allow(Resolv).to receive(:getaddress).and_raise(Resolv::ResolvError)
      expect(Geolocation.for_query("nonexistent.example.invalid")).to be_empty
    end
  end
end
