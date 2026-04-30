module Authenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate!
  end

  private

  def authenticate!
    api_key = request.headers["X-Api-Key"]
    return if api_key.present? && api_key == ENV.fetch("API_KEY", nil)

    render json: {
      errors: [ { status: "401", code: "unauthorized", title: "Unauthorized" } ]
    }, status: :unauthorized
  end
end
