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
  #     :port => 5656,
  #     :host => 'localhost'
  #   })
  #   client.run
  #
  class Client
    def self.opts_parser(options = {})
      opts = OptionParser.new
      opts.banner = 'Usage: rrails [options] [[--] commands]'
      opts.on('-h', '--help', 'This help.')      {|v| options[:help] = v }
      opts.on('--host=s', 'RRails server hostname. Default value is "localhost".')      {|v| options[:host] = v }
      opts.on('-E', '--rails_env=s') {|v| options[:rails_env] = v }
      opts.on('-p', '--port=i', 'RRails server port. Default value is decided from RAILS_ENV.')      {|v| options[:port] = v }
      opts.on('-t', '--[no-]pty', "Prepare a PTY. Default value is decided by commands.")      {|v| options[:pty] = v }
      return opts
    end

    def self.new_with_options(argv)
      options = {}
      opts_parser(options).parse!(argv)

      cmd = Shellwords.join(argv)
      options[:cmd] = cmd == "" ? nil : cmd
      self.new(options)
    end

    def initialize(options={})
      @cmd = options[:cmd] || ""
      @host = options[:host] || 'localhost'
      @rails_env = options[:rails_env] || ENV['RAILS_ENV'] || 'development'
      @port = options[:port] || DEFAULT_PORT[@rails_env]
      @use_pty = options[:pty]
      if @use_pty.nil?
        # decide use_pty from cmd
        case @cmd
        when /^rails (?:c(?:onsole)?|db(?:console)?)$/, 'pry'
          @use_pty = true
        end
      end
    end

    def run
      if @cmd.empty?
        STDERR.puts Client.opts_parser
        return
      end

      sock = TCPSocket.open(@host, @port)
      sock.puts("#{@use_pty ? 'P' : ' '}#@cmd")
      running = true

      begin
        # input thread
        thread = Thread.start do
          while running do
            begin
              input = @use_pty ? STDIN.getch : STDIN.gets
              sock.write(input)
              sock.flush
            rescue
              running = false
              sock.close unless sock.closed?
            end
          end
        end

        while running && line = sock.gets
          case line.chomp
          when /^EXIT\t(.+)$/
            exit($1.to_i)
          when /^OUT\t(.+)$/
            STDOUT.write($1.split(',').map(&:to_i).pack('c*'))
          when /^ERR\t(.+)$/
            STDERR.write($1.split(',').map(&:to_i).pack('c*'))
          end
        end

      rescue EOFError
        running = false
      rescue Interrupt
        running = false
        exit 130
      end

      STDERR.puts "\nERROR: RRails server disconnected"
      exit -1
    end

  end
end
