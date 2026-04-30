Mime::Type.register "application/vnd.api+json", :jsonapi

ActionDispatch::Request.parameter_parsers[Mime[:jsonapi].symbol] =
  ActionDispatch::Request.parameter_parsers[Mime[:json].symbol]
