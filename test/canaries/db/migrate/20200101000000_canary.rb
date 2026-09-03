class Canary < ActiveRecord::Migration[7.0]
  def change
    add_column :canary_records, :thing, :string, null: true
  end
end
