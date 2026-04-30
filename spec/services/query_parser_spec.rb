require "rails_helper"

RSpec.describe QueryParser do
  describe "#parse" do
    context "bare IPv4" do
      it "returns the IP and nil url_hostname" do
        result = described_class.new("8.8.8.8").parse
        expect(result).to eq({ ip: "8.8.8.8", url_hostname: nil })
      end
    end

    context "bare IPv6" do
      it "returns the IP and nil url_hostname" do
        result = described_class.new("2001:4860:4860::8888").parse
        expect(result).to eq({ ip: "2001:4860:4860::8888", url_hostname: nil })
      end
    end

    context "full URL" do
      it "resolves hostname to IP and stores extracted hostname in url_hostname" do
        allow(Resolv).to receive(:getaddress).with("google.com").and_return("142.250.74.46")
        result = described_class.new("https://google.com/search?q=hello").parse
        expect(result[:ip]).to eq("142.250.74.46")
        expect(result[:url_hostname]).to eq("google.com")
      end

      it "raises UnresolvableHost when domain does not resolve" do
        allow(Resolv).to receive(:getaddress).and_raise(Resolv::ResolvError)
        expect { described_class.new("https://nonexistent.invalid").parse }
          .to raise_error(QueryParser::UnresolvableHost)
      end
    end

    context "hostname without protocol" do
      it "resolves hostname to IP and stores hostname in url_hostname" do
        allow(Resolv).to receive(:getaddress).with("cloudflare.com").and_return("104.16.132.229")
        result = described_class.new("cloudflare.com").parse
        expect(result[:ip]).to eq("104.16.132.229")
        expect(result[:url_hostname]).to eq("cloudflare.com")
      end

      it "raises UnresolvableHost when domain does not resolve" do
        allow(Resolv).to receive(:getaddress).and_raise(Resolv::ResolvError)
        expect { described_class.new("nonexistent.invalid").parse }
          .to raise_error(QueryParser::UnresolvableHost)
      end
    end

    context "invalid input" do
      it "raises InvalidQuery for garbage string" do
        expect { described_class.new("!!!").parse }.to raise_error(QueryParser::InvalidQuery)
      end

      it "raises InvalidQuery for malformed IP" do
        expect { described_class.new("999.999.999.999").parse }.to raise_error(QueryParser::InvalidQuery)
      end

      it "raises InvalidQuery for single-label input without dots" do
        expect { described_class.new("not-an-ip").parse }.to raise_error(QueryParser::InvalidQuery)
      end
    end

    context "reserved IP" do
      it "raises ReservedIpAddress for private range 192.168.x.x" do
        expect { described_class.new("192.168.1.1").parse }.to raise_error(QueryParser::ReservedIpAddress)
      end

      it "raises ReservedIpAddress for loopback 127.0.0.1" do
        expect { described_class.new("127.0.0.1").parse }.to raise_error(QueryParser::ReservedIpAddress)
      end

      it "raises ReservedIpAddress for private range 10.x.x.x" do
        expect { described_class.new("10.0.0.1").parse }.to raise_error(QueryParser::ReservedIpAddress)
      end

      it "raises ReservedIpAddress for IPv6 loopback ::1" do
        expect { described_class.new("::1").parse }.to raise_error(QueryParser::ReservedIpAddress)
      end
    end
  end
end
