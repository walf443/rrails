require 'socket'
require 'rrails'
require 'logger'
require 'rake'
require 'stringio'
require 'shellwords'

# FIXME: rails command require APP_PATH constants.
APP_PATH = File.expand_path('./config/application')

module RemoteRails
  # server to run rails/rake command.
  #
  #   @example
  #     server = RemoteRails::Server.new(:rails_env => "development")
  #     server.start
  #
  class Server
    def initialize(options={})
      @rails_env = options[:rails_env] || "development"
      @app_path = File.expand_path('./config/application')
      # should not access to outside
      @host = 'localhost'
      @port = options[:port] || DEFAULT_PORT[@rails_env]
      @logger = Logger.new(options[:logfile] ? options[:logfile] : $stderr)
    end

    def start
      self.boot_rails
      server = TCPServer.open(@host, @port)
      @logger.info("starting rrails server on #{@host}:#{@port}")
      trap(:INT) do
        @logger.info("SIGINT recieved. shutdown...")
        exit
      end
      trap(:TERM) do
        @logger.info("SIGTERM recieved. shutdown...")
        exit
      end
      trap(:HUP) do
        @logger.info("SIGHUP recieved. reload...")
        ActionDispatch::Callbacks.new(Proc.new {}).call({})
        self.boot_rails
      end
      Thread.abort_on_exception = true
      loop do
        Thread.start(server.accept) do |s|
          childpids = []
          begin
            while line = s.gets
              line.chomp!
              @logger.info("invoke: #{line}")
              start = Time.now
              self.dispatch(s, line) { |pid| childpids << pid }
              finish = Time.now
              s.puts("FINISHED\t#{ finish - start }")
              @logger.info("finished: #{line}")
            end
          rescue Errno::EPIPE => e
            Process.kill 'TERM', *childpids unless childpids.empty?
            @logger.error("client disconnect: " + e.message)
          end
        end
      end
    end

    def boot_rails
      @logger.info("prepare rails environment")
      ENV["RAILS_ENV"] = @rails_env
      require File.expand_path('./config/boot')
      require @app_path
      Rails.application.require_environment!
      unless Rails.application.config.cache_classes
        ActionDispatch::Reloader.cleanup!
        ActionDispatch::Reloader.prepare!
      end
      @logger.info("finished preparing rails environment")
    end

    def dispatch(sock, line)
      args = Shellwords.shellsplit(line)
      subcmd = args.shift
      servsock_out, clisock_out = UNIXSocket.pair
      servsock_err, clisock_err = UNIXSocket.pair
      pid = fork do
        clisock_out.close
        clisock_err.close
        ActiveRecord::Base.establish_connection if defined?(ActiveRecord::Base)
        STDOUT.reopen(servsock_out)
        STDERR.reopen(servsock_err)
        self.__send__("on_#{subcmd}", args)
      end
      yield pid
      servsock_out.close
      servsock_err.close
      buffers = {out: '', error: ''}
      clisocks = {out: clisock_out, error: clisock_err}
      loop do
        if Process.waitpid(pid, Process::WNOHANG)
          return
        end
        [:out, :error].each do |channel|
          begin
            buffers[channel] << clisocks[channel].read_nonblock(4096)
            while buffers[channel][/[\n\r]/]
              line, buffers[channel] = buffers[channel].split(/[\n\r]/, 2)
              sock.puts("#{channel.upcase}\t#{line}")
            end
          rescue Errno::EAGAIN, EOFError => ex
            sleep 0.1
          end
        end
      end
    end

    def on_rails(args)
      ARGV.clear
      ARGV.concat(args)
      require 'rails/commands'
    end

    def on_rake(args)
      ARGV.clear
      ARGV.concat(args)
      ::Rake.application.run
    end
  end
end
