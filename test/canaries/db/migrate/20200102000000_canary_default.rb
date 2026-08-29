class CanaryDefault < ActiveRecord::Migration[7.0]
  def change
    add_column :canaries, :state, :string, null: false, default: "held"
  end
end
