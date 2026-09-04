class Deed
  def self.call(**arguments)
    new(**arguments).call
  end
end
