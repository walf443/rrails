require 'socket'
require 'rrails'
require 'shellwords'
require 'optparse'
require 'io/console'

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
      running = true

      begin
        # input thread
        thread = Thread.start do
          while running do
            input = STDIN.getch
            sock.write(input)
          end
        end

        while running && line = sock.gets.chomp
          case line
          when /^FINISHED\t(.+)$/
            # kill the input thread immediately
            exit 0
          when /^OUT\t(.+)$/
            STDOUT.write($1.split(',').map(&:to_i).pack('c*'))
          when /^ERR\t(.+)$/
            STDERR.write($1.split(',').map(&:to_i).pack('c*'))
          end
        end
      rescue EOFError
        running = false
      ensure
        running = false
      end
    end

  end
end
