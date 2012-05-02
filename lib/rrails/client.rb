require 'socket'
require 'rrails'
require 'shellwords'
require 'optparse'
module RemoteRails
  #
  # client for RemoteRails::Server.
  #
  # @example
  #   client = RemoteRails::Client.new({
  #     :cmd => "rails generate model Sushi",
  #     :rails_env => "development",
  #   })
  #   client.run
  #
  class Client
    def self.new_with_options(argv)
      options = {}
      opts = OptionParser.new
      opts.on('-E', '--rails_env=s') {|v| options[:rails_env] = v }
      opts.on('-p', '--port=i')      {|v| options[:port] = v }
      opts.parse!(argv)

      cmd = Shellwords.join(argv)
      options[:cmd] = cmd == "" ? nil : cmd
      self.new(options)
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
        if line =~ /^FINISHED\t(.+)/
          $stdout.puts("\nfinished (#{$1}sec)")
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
