module RemoteRails

  if not defined?(DEFAULT_PORT)
    DEFAULT_PORT = {
      "development" => 5656,
      "test" => 5657,
      "production" => 5658,
    }
  end

end
