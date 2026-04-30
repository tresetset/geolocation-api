class CreateGeolocations < ActiveRecord::Migration[8.1]
  def change
    create_table :geolocations, id: :uuid do |t|
      t.inet :ip, null: false
      t.string :url_hostname
      t.string :ip_type, null: false
      t.string :country_code, limit: 2
      t.string :city
      t.decimal :latitude, precision: 9, scale: 6, null: false
      t.decimal :longitude, precision: 9, scale: 6, null: false

      t.timestamps
    end

    add_index :geolocations, :ip, unique: true
  end
end
