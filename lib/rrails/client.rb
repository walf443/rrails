require 'socket'
require 'rrails'
module RemoteRails
  class Client
    def self.new_with_options(argv)
      self.new({ :cmd => argv })
    end

    def initialize(options={})
      @cmd = options[:cmd] || "rails"
      @rails_env = options[:rails_env] || 'development'
      @host = options[:host] || 'localhost'
      @port = options[:port] || DEFAULT_PORT[@rails_env]
    end

    def run
      sock = TCPSocket.open(@host, @port)
      sock.puts(@cmd)
      while line = sock.gets
        puts line
        if line =~ /^finished\t/
          return
        end
      end
    end
  end
end
