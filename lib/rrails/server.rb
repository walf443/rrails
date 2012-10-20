require 'socket'
require 'rrails'
require 'logger'
require 'rake'
require 'stringio'
require 'shellwords'
require 'pty'
require 'benchmark'
require 'fileutils'


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
      @rails_env  = options[:rails_env] || ENV['RAILS_ENV'] || "development"
      @pidfile    = "#{options[:pidfile] || './tmp/pids/rrails-'}#{@rails_env}.pid"
      @background = options[:background] || false
      @host       = options[:host] || 'localhost'
      @port       = options[:port] || DEFAULT_PORT[@rails_env]
      @socket     = "#{options[:socket] || './tmp/sockets/rrails-'}#{@rails_env}.socket"
      if (options[:host] || options[:port]) && !options[:socket]
        @socket = nil
      end
      @app_path   = File.expand_path('./config/application')
      @logger     = Logger.new(options[:logfile] ? options[:logfile] : (@background ? nil : STDERR))
      @logger.level = options[:loglevel] || 0
    end

    def stop
      pid = previous_instance
      if pid
        @logger.info "stopping previous instance #{pid}"
        Process.kill :TERM, pid
        FileUtils.rm_f [@socket, @pidfile]
        return true
      end
    end

    def restart
      stop && sleep(1)
      start
    end

    def reload
      pid = previous_instance
      Process.kill :HUP, pid
    end

    def alive?
      previous_instance ? true : false
    end

    def status
      pid = previous_instance
      if pid
        puts "running \tpid = #{pid}"
      else
        puts 'stopped'
      end
    end

    def start
      # check previous process
      raise RuntimeError.new('rrails is already running') if alive?

      if @background
        pid = Process.fork do
          @background = false
          start
        end
        Process.detach(pid)
        return
      end

      # make 'bundle exec' not necessary for most time.
      require 'bundler/setup'

      begin
        [@pidfile, @socket].compact.each do |path|
          FileUtils.rm_f path
          FileUtils.mkdir_p File.dirname(path)
        end

        File.write(@pidfile, $$)
        server = if @socket
                   UNIXServer.open(@socket)
                 else
                   TCPServer.open(@host, @port)
                 end
        server.close_on_exec = true

        @logger.info("starting rrails server: #{@socket || "#{@host}:#{@port}"}")

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

        self.boot_rails

        Thread.abort_on_exception = true

        loop do
          Thread.start(server.accept) do |s|
            @logger.debug("accepted")
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
              s.flush
              @logger.info("finished: #{line} (#{time} seconds)")
            rescue Errno::EPIPE
              @logger.info("disconnected: #{line}")
            end
          end
        end
      ensure
        server.close unless server.closed?
        @logger.info("cleaning pid and socket files...")
        FileUtils.rm_f [@socket, @pidfile].compact
      end
    end

    def boot_rails
      @logger.info("prepare rails environment (#{@rails_env})")
      ENV["RAILS_ENV"] = @rails_env

      # make IRB = Pry hacks (https://gist.github.com/941174) work:
      # pre-require all irb compoments needed in rails/commands
      # otherwise 'module IRB' will cause 'IRB is not a module' error.
      require 'irb'
      require 'irb/completion'

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
      heartbeat = 0

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
        heartbeat += 1
        if heartbeat > 20
          sock.puts("PING")
          sock.flush
          heartbeat = 0
        end

        # do not make CPU hot
        sleep 0.025
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

    private

    def execute(cmd, *args)
      ARGV.clear
      ARGV.concat(args)
      $0 = cmd
      case cmd
      when 'rails'
        require 'rails/commands'
      when 'rake'
        # full path of rake
        $0 = Gem.bin_path('rake')
        ::Rake.application.run
      else
        # unknown binary, try to locate its location
        bin_path = begin
                     Gem.bin_path(cmd)
                   rescue
                     STDERR.puts "rrails: command not found: #{cmd}"
                     STDERR.puts "Install missing gem executables with `bundle install`"
                     exit(127)
                   end

        # then load it
        load bin_path
      end
    end

    def previous_instance
      begin
        previous_pid = File.read(@pidfile).to_i

        if previous_pid > 0 && Process.kill(0, previous_pid)
          return previous_pid
        end
        return false
      rescue Errno::ESRCH, Errno::ENOENT
        return false
      end
    end

  end
end
