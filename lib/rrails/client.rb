require 'socket'
require 'rrails'
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
    def initialize(options={})
      @cmd = options[:cmd] || ""

      @rails_env = options[:rails_env] || ENV['RAILS_ENV'] || 'development'


      @use_pty = options[:pty]
      @ondemand_callback = options[:ondemand_callback]

      if @cmd.is_a? Array
        require 'shellwords'
        @cmd = Shellwords.join(@cmd)
      end

      if (options[:host] || options[:port]) && !options[:socket]
        @socket = nil
        @host = options[:host] || 'localhost'
        @port = options[:port] || DEFAULT_PORT[@rails_env]
      else
        @socket = "#{options[:socket] || './tmp/sockets/rrails-'}#{@rails_env}.socket"
      end

      if @use_pty.nil?
        # decide use_pty from cmd
        case @cmd
        when /^rails (?:c(?:onsole)?|db(?:console)?)$/, 'pry'
          @use_pty = true
        end
      end
    end

    def run
      sock = nil
      begin
        sock = connect
      rescue
        if @ondemand_callback
          @ondemand_callback.call
          sock = connect
        end
      end

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
            return $1.to_i
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
        return 130
      ensure
        running = false
        thread.kill
      end

      STDERR.puts "\r\nERROR: RRails server disconnected"
      return -1
    end

    private

    def connect
      if @socket
        UNIXSocket.open(@socket)
      else
        TCPSocket.open(@host, @port)
      end
    end

  end

end
