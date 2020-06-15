# frozen_string_literal: true

require 'socket'

module Server
  def self.start_echo_server(host: '::', port: 3000)
    setup = lambda do |ready|
      TCPServer.open(host, port) do |server|
        ready.call
        loop do
          socket = server.accept
          IO.copy_stream(socket, socket)
        ensure
          socket&.close
        end
      end
    end
    run(setup) { yield }
  end

  def self.start_udp_echo_server(port: 3002)
    setup = lambda do |ready|
      udp = UDPSocket.new(:INET6)
      udp.bind('::', port)
      ready.call
      loop do
        msg, addr = udp.recvfrom(64)
        udp.send msg, 0, addr[3], addr[1]
      end
    ensure
      udp.close
    end
    run(setup) { yield }
  end

  def self.start_dead_server(host: '::', port: 3001)
    TCPServer.open(host, port) do |server|
      server.listen(0)
      Socket.tcp('::1', port) { yield }
    end
  end

  def self.run(setup)
    queue = Queue.new
    Thread.new do
      ready = proc { queue.push(Thread.current) }
      setup.call(ready)
    end
    thread = queue.pop
    begin
      yield
    ensure
      thread.kill
    end
  end
  private_class_method :run
end
