ActionDispatch::RequestEncoder.register_encoder(
  :jsonapi,
  param_encoder:   ->(params) { params.to_json },
  response_parser: ->(body) { JSON.parse(body, object_class: ActiveSupport::HashWithIndifferentAccess) }
)
