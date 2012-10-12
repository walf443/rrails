require 'socket'
require 'rrails'
require 'logger'
require 'rake'
require 'stringio'
require 'shellwords'
require 'pty'
require 'irb'
require 'pry'

# FIXME: rails command require APP_PATH constants.
APP_PATH = File.expand_path('./config/application')
PAGE_SIZE = 4096

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
            line = s.gets.chomp
            @logger.info("invoke: #{line}")
            start = Time.now
            self.dispatch(s, line) { |pid| childpids << pid }
            finish = Time.now
            s.puts("FINISHED\t#{ finish - start }")
            @logger.info("finished: #{line} (in #{finish - start} seconds)")
          rescue Errno::EPIPE => e
            @logger.error("client disconnect: " + e.message)
            Process.kill 'TERM', *childpids unless childpids.empty?
          end
        end
      end
    end

    def boot_rails
      @logger.info("prepare rails environment (#{@rails_env})")
      ENV["RAILS_ENV"] = @rails_env
      require File.expand_path('./config/application')
      require File.expand_path('./config/boot')
      require File.expand_path('./config/environment')
      require @app_path
      Rails.application.require_environment!
      unless Rails.application.config.cache_classes
        ActionDispatch::Reloader.cleanup!
        ActionDispatch::Reloader.prepare!
      end
      @logger.info("finished preparing rails environment")
    end

    def dispatch(sock, line)
      m_out, s_out = PTY.open
      m_err, s_err = PTY.open

      # servsock_out, clisock_out = UNIXSocket.pair
      # servsock_err, clisock_err = UNIXSocket.pair

      running = true
      pid = fork do
        # [m_out, m_err].each(&:close)
        ActiveRecord::Base.establish_connection if defined?(ActiveRecord::Base)
        STDIN.reopen(s_out)
        STDOUT.reopen(s_out)
        STDERR.reopen(s_err)
        execute *Shellwords.shellsplit(line)
      end

      yield pid

      # input thread
      thread = Thread.start do
        while running do
          begin
            input = sock.getc
            m_out.write(input)
          rescue
            running = false
          end
        end
      end

      clisocks = {out: m_out, err: m_err}
      loop do
        return $? if Process.waitpid(pid, Process::WNOHANG)
        [:out, :err].each do |channel|
          begin
            response = clisocks[channel].read_nonblock(PAGE_SIZE)
            sock.puts("#{channel.upcase}\t#{response.bytes.to_a.join(',')}")
            sock.flush
          rescue Errno::EAGAIN, EOFError => ex
            sleep 0.1
          end
        end
      end
    ensure
      running = false
      [m_out, m_err].each {|io| io.close unless io.closed?}
      Process.kill 'TERM', pid rescue nil
      thread.join if thread
    end

    def execute(cmd, *args)
      ARGV.clear
      ARGV.concat(args)
      case cmd
      when 'rails'
        require 'rails/commands'
      when 'rake'
        ::Rake.application.run
      else
        @logger.warn "#{cmd} not supported"
        raise RuntimeError.new("#{cmd} is not supported in rrails.")
      end
    end

  end
end
