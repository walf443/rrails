require 'socket'
require 'rrails'
require 'shellwords'
module RemoteRails
  class Client
    def self.new_with_options(argv)
      cmd = Shellwords.join(argv)
      self.new({ :cmd => cmd })
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
        if line =~ /^FINISHED\t/
          return
        elsif line =~ /^OUT\t(.+)$/
          $stdout.puts($1)
        elsif line =~ /^ERROR\t(.+)$/
          $stderr.puts($1)
        end
      end
    end
  end
end
