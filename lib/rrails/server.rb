require 'socket'
require 'rrails'
require 'logger'
require 'rake'
require 'stringio'

# FIXME: rails command require APP_PATH constants.
APP_PATH = File.expand_path('./config/application')

module RemoteRails
  class Server
    def initialize(options={})
      @rails_env = options[:rails_env] || "development"
      @app_path = File.expand_path('./config/application')
      # should not access to outside
      @host = 'localhost'
      @port = options[:poot] || DEFAULT_PORT[@rails_env]
      @logger = Logger.new(options[:logfile] ? options[:logfile] : $stderr)
    end

    def boot_rails
      @logger.info("prepare rails environment")
      ENV["RAILS_ENV"] = @rails_env
      require File.expand_path('./config/boot')
      require @app_path
      Rails.application.require_environment!
      @logger.info("finished preparing rails environment")
    end

    def start
      self.boot_rails
      server = TCPServer.open(@host, @port)
      @logger.info("starting rrails server on #{@host}:#{@port}")
      Thread.abort_on_exception = true
      loop do
        Thread.start(server.accept) do |s|
          while line = s.gets
            @logger.info("invoke: #{line}")
            start = Time.now
            self.dispatch(s, line)
            finish = Time.now
            s.puts("finished\t#{ finish - start }")
            @logger.info("finished: #{line}")
          end
        end
      end
    end

    def dispatch(sock, line)
      args = line.split(/\s+/)
      subcmd = args.shift
      ActiveRecord::Base.remove_connection if defined?(ActiveRecord::Base)
      servsock, clisock = UNIXSocket.pair
      pid = fork do
        clisock.close
        ActiveRecord::Base.establish_connection if defined?(ActiveRecord::Base)
        STDOUT.reopen(servsock)
        STDERR.reopen(servsock)
        self.__send__("on_#{subcmd}", args)
      end
      servsock.close
      loop do
        if Process.waitpid(pid, Process::WNOHANG)
          return
        end
        if IO.select([clisock], [], [], 0.1)
          while line = clisock.gets
            sock.puts(line)
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
      ::Rake.application = ::Rake::Application.new
      ::Rake.application.init
      ::Rake.application.load_rakefile
      ::Rake.application[:environment].invoke
      name = args.shift
      ::Rake.application[name].invoke
    end
  end
end
