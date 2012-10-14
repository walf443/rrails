require 'socket'
require 'rrails'
require 'logger'
require 'rake'
require 'stringio'
require 'shellwords'
require 'pty'
require 'benchmark'

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
    PAGE_SIZE = 4096

    def initialize(options={})
      @rails_env = options[:rails_env] || ENV['RAILS_ENV'] || "development"
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

      [:INT, :TERM].each do |sig|
        trap(sig) do
          @logger.info("SIG#{sig} recieved. shutdown...")
          exit
        end
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
            pty, line = (line[0] == 'P'), line[1..-1]
            @logger.info("invoke: #{line} (pty=#{pty})")
            status = nil
            time = Benchmark.realtime do
              status = dispatch(s, line, pty)
            end
            exitcode = status ? status.exitstatus || (status.termsig + 128) : 0
            s.puts("EXIT\t#{exitcode}")
            @logger.info("finished: #{line} (#{time} seconds)")
          rescue Errno::EPIPE
            @logger.info("disconnected: #{line}")
          end
        end
      end
    end

    def boot_rails
      @logger.info("prepare rails environment (#{@rails_env})")
      ENV["RAILS_ENV"] = @rails_env
      require File.expand_path('./config/environment')

      unless Rails.application.config.cache_classes
        ActionDispatch::Reloader.cleanup!
        ActionDispatch::Reloader.prepare!
      end
      @logger.info("finished preparing rails environment")
    end

    def dispatch(sock, line, pty=false)
      if pty
        m_out, c_out = PTY.open
        c_in = c_err = c_out
        m_fds = [m_out, c_out]
        c_fds = [c_out]
        clisocks = {in: m_out, out: m_out}
      else
        c_in, m_in = IO.pipe
        m_out, c_out = IO.pipe
        m_err, c_err = IO.pipe
        m_fds = [m_in, m_out, m_err]
        c_fds = [c_in, c_out, c_err]
        clisocks = {in: m_in, out: m_out, err: m_err}
      end

      running = true
      pid = fork do
        m_fds.map(&:close) if not pty
        STDIN.reopen(c_in)
        STDOUT.reopen(c_out)
        STDERR.reopen(c_err)
        ActiveRecord::Base.establish_connection if defined?(ActiveRecord::Base)
        execute *Shellwords.shellsplit(line)
      end

      c_fds.map(&:close) if not pty

      # pump input. since it will block, make it in another thread
      thread = Thread.start do
        while running do
          begin
            input = sock.__send__(pty ? :getc : :gets)
          rescue => ex
            @logger.debug "input thread got #{ex}"
            running = false
          end
          clisocks[:in].write(input) rescue nil
        end
      end

      loop do
        [:out, :err].each do |channel|
          next if not clisocks[channel]
          begin
            loop do
              response = clisocks[channel].read_nonblock(PAGE_SIZE)
              sock.puts("#{channel.upcase}\t#{response.bytes.to_a.join(',')}")
              sock.flush
            end
          rescue Errno::EAGAIN, EOFError => ex
            next
          end
        end

        if running
          _, stat = Process.waitpid2(pid, Process::WNOHANG)
          if stat
            @logger.debug "child exits. #{stat}"
            return stat
          end
        end

        # send heartbeat so that we got EPIPE immediately when client dies
        sock.puts("PING")
        sock.flush

        # do not make CPU hot
        sleep 0.1
      end
    ensure
      running = false
      [*c_fds, *m_fds].each {|io| io.close unless io.closed?}
      if pid
        begin
          Process.kill 0, pid
          @logger.debug "killing pid #{pid}"
          Process.kill 'TERM', pid rescue nil
        rescue Errno::ESRCH
        end
      end
      thread.kill if thread
    end

    def execute(cmd, *args)
      ARGV.clear
      ARGV.concat(args)
      case cmd
      when 'rails'
        require 'rails/commands'
      when 'rake'
        ::Rake.application.run
      when 'pry'
        Pry::CLI.parse_options
      else
        STDERR.puts "#{cmd} is not supported in RRails."
      end
    end

  end
end
