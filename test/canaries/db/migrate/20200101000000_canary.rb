class Canary < ActiveRecord::Migration[7.0]
  def change
    add_column :canaries, :thing, :string, null: true
  end
end
