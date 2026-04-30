module Api
  module V1
    class GeolocationsController < ApplicationController
      def index
        filter = params.dig(:filter, :query)
        scope = filter.present? ? Geolocation.for_query(filter) : Geolocation.all
        pagy, geolocations = pagy(scope)

        render json: GeolocationSerializer.new(geolocations).serializable_hash.merge(
          meta: { page: pagy.page, per_page: pagy.limit, total: pagy.count },
          links: pagination_links(pagy),
          jsonapi: { version: "1.1" }
        )
      end

      def show
        geolocation = Geolocation.find(params[:id])
        render json: GeolocationSerializer.new(geolocation).serializable_hash.merge(jsonapi: { version: "1.1" })
      end

      def create
        query = params.dig(:data, :attributes, :query)
        return render_missing_parameter if query.blank?

        result = GeolocationService.new(provider: provider).call(query)

        geolocation = result[:geolocation]
        serialized = GeolocationSerializer.new(geolocation).serializable_hash.merge(jsonapi: { version: "1.1" })

        if result[:status] == :created
          response.headers["Location"] = "/api/v1/geolocations/#{geolocation.id}"
          render json: serialized, status: :created
        else
          render json: serialized, status: :ok
        end
      end

      def destroy
        Geolocation.find(params[:id]).destroy!
        head :no_content
      end

      private

      def provider
        GeolocationProviderFactory.build
      end

      def pagination_links(pagy)
        base_url = "#{request.base_url}#{request.path}"
        base_params = request.query_parameters.except("page")
        build = ->(page) { page ? "#{base_url}?#{base_params.merge('page' => page).to_query}" : nil }
        { first: build.call(1), last: build.call(pagy.last), next: build.call(pagy.next), prev: build.call(pagy.prev) }
      end
    end
  end
end
