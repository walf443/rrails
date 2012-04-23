require 'socket'
require 'rrails'
require 'logger'
require 'rake'
require 'stringio'

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
            self.dispatch(line)
            finish = Time.now
            s.puts("finished\t#{ finish - start }")
          end
        end
      end
    end

    def dispatch(line)
      args = line.split(/\s+/)
      subcmd = args.shift
      self.__send__("on_#{subcmd}", args)
    end

    def on_rails(args)
      ActiveRecord::Base.remove_connection if defined?(ActiveRecord::Base)
      pid = fork do
        ActiveRecord::Base.establish_connection if defined?(ActiveRecord::Base)
        ARGV.clear
        ARGV.concat(args)
        require 'rails/commands'
      end
      Process.waitpid(pid)
    end

    def on_rake(args)
      ActiveRecord::Base.remove_connection if defined?(ActiveRecord::Base)
      pid = fork do
        ActiveRecord::Base.establish_connection if defined?(ActiveRecord::Base)
        ::Rake.application = ::Rake::Application.new
        ::Rake.application.init
        ::Rake.application.load_rakefile
        ::Rake.application[:environment].invoke
        name = args.shift
        ::Rake.application[name].invoke
      end
      Process.waitpid(pid)
    end
  end
end
