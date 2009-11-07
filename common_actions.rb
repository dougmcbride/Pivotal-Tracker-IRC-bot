module CommonActions
  def initialize(*args)
    super

    add_actions \
      /#{nick}, join (#\w+)/ => lambda {|n,e,m| join m[1]; reply(e, "Ok.")},
      /#{nick}, (?:part|leave|exit) (#\w+)/ => lambda {|n,e,m| part m[1]; reply(e, "Ok.")}
  end
end
