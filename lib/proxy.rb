# frozen_string_literal: true

require 'csv'
require 'socket'
require 'time'

class Proxy < EventMachine::Connection
  def initialize(opts)
    super
    @buf = nil
    @client_ip, @client_port = client_ip_port
    @failed = false
    @host = nil
    @port = nil
    @quiet = opts[:quiet]
    @connect_timeout = opts[:connect_timeout]
    @server = nil
  end

  def receive_data(data)
    return if @failed
    @buf ? @buf << data : @buf = data
    done = receive_message(@buf)
    @buf = nil if done || @failed
  end

  def unbind
    return unless @server

    log('success', get_proxied_bytes) unless @failed

    @server.close_connection_after_writing
    @server = nil
  end

  private

  def client_ip_port
    addrinfo = Addrinfo.new(get_peername || return)
    addrinfo.ip_unpack if addrinfo.ip?
  end

  def proxy_to(host, port)
    completion = EventMachine::Completion.new
    @host, @port = host, port
    begin
      @server = EventMachine.connect(host, port, Server, completion)
    rescue => e
      completion.fail(e)
    else
      @server.pending_connect_timeout = @connect_timeout
      proxy_incoming_to(@server)
      @server.proxy_incoming_to(self)
    end
    completion
  end

  def failure(comment, data = nil)
    @failed = true
    comment = "#{comment}: #{dump(data)}" if data
    log('failure', comment)
    close_connection_after_writing
  end

  def log(status, comment)
    return if @quiet
    row = [
      Time.now.iso8601(3),
      @client_ip || '-',
      @client_port || '-',
      @host || '-',
      @port || '-',
      self.class.name.downcase,
      status,
      comment.to_s
    ]
    puts CSV.generate_line(row, col_sep: ' ')
  end

  def dump(data, size: 32)
    data[0, size].dump[1...-1]
  end

  class Server < EventMachine::Connection
    def initialize(completion)
      super
      @completion = completion
      @connected = false
    end

    def connection_completed
      @connected = true
      @completion.succeed(self)
    end

    def unbind(errno)
      @completion.fail(errno) unless @connected
    end
  end
  private_constant :Server
end
