class CanaryCop < Base
  MSG = "Do not do that."

  def on_send(node)
    add_offense(node)
  end
end
