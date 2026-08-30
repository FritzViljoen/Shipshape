class Workflow
  def self.call(**arguments)
    new(**arguments).__perform__
  end
end
