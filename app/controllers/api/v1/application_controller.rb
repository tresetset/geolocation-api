module Api
  module V1
    class ApplicationController < ::ApplicationController
      include Authenticatable

      JSONAPI_CONTENT_TYPE = "application/vnd.api+json"

      before_action :set_jsonapi_content_type
      before_action :require_jsonapi_content_type, only: %i[create]

      rescue_from ActiveRecord::RecordNotFound, with: :not_found
      rescue_from Pagy::OverflowError,          with: :page_overflow

      rescue_from QueryParser::InvalidQuery,       with: :invalid_query
      rescue_from QueryParser::ReservedIpAddress,  with: :reserved_ip_address
      rescue_from QueryParser::UnresolvableHost,   with: :unresolvable_host

      rescue_from ActiveRecord::RecordInvalid, with: :record_invalid

      rescue_from GeolocationProvider::ProviderUnavailable,  with: :provider_unavailable
      rescue_from GeolocationProvider::ProviderRateLimited,  with: :provider_rate_limited
      rescue_from GeolocationProvider::ProviderError,        with: :provider_error

      private

      def set_jsonapi_content_type
        response.content_type = JSONAPI_CONTENT_TYPE
      end

      def require_jsonapi_content_type
        return if request.content_type == JSONAPI_CONTENT_TYPE

        render json: {
          errors: [ { status: "415", code: "unsupported_media_type", title: "Unsupported Media Type" } ]
        }, status: :unsupported_media_type
      end

      def not_found
        render_error(status: :not_found, code: "not_found", title: "Not Found")
      end

      def page_overflow
        render json: { errors: [ { status: "400", title: "Page overflow" } ] }, status: :bad_request
      end

      def invalid_query
        render_query_error(code: "invalid_query", title: "Invalid query")
      end

      def reserved_ip_address
        render_query_error(code: "reserved_ip_address", title: "Reserved IP address")
      end

      def unresolvable_host
        render_query_error(code: "unresolvable_host", title: "Unresolvable host")
      end

      def record_invalid(exception)
        errors = exception.record.errors.map do |error|
          {
            status: "422",
            code: "invalid_#{error.attribute}",
            title: error.full_message,
            source: { pointer: "/data/attributes/#{error.attribute}" }
          }
        end
        render json: { errors: errors }, status: :unprocessable_content
      end

      def provider_unavailable
        render_error(status: :service_unavailable, code: "provider_unavailable", title: "Provider unavailable")
      end

      def provider_rate_limited
        render_error(status: :service_unavailable, code: "provider_rate_limited", title: "Provider rate limited")
      end

      def provider_error
        render_error(status: :bad_gateway, code: "provider_error", title: "Provider error")
      end

      def render_error(status:, code:, title:)
        render json: {
          errors: [ { status: Rack::Utils.status_code(status).to_s, code: code, title: title } ]
        }, status: status
      end

      def render_missing_parameter
        render json: {
          errors: [ {
            status: "400",
            code: "missing_parameter",
            title: "Missing parameter",
            source: { pointer: "/data/attributes/query" }
          } ]
        }, status: :bad_request
      end

      def render_query_error(code:, title:)
        render json: {
          errors: [ {
            status: "422",
            code: code,
            title: title,
            source: { pointer: "/data/attributes/query" }
          } ]
        }, status: :unprocessable_content
      end
    end
  end
end
