VCR.configure do |config|
  config.cassette_library_dir = "spec/cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!
  config.ignore_localhost = true
  config.filter_sensitive_data("<IPSTACK_KEY>") { ENV["IPSTACK_ACCESS_KEY"] }
end
