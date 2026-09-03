class Command
  def self.call(**arguments)
    new(**arguments).call
  end
end
