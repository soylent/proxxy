# encoding: binary
# frozen_string_literal: true

require 'ipaddr'
require 'tmpdir'

require_relative 'helper'
require_relative 'server'

# cutest[:only] = 'that it ignores incomming data after a failure'

test 'that it checks options' do
  assert_proxxy('--oiujif', stderr: 'invalid option', success: false)
end

test 'that it shows help' do
  assert_proxxy('--help', stdout: 'Usage:')
end

test 'that it shows version' do
  assert_proxxy('--version', stdout: /\A\d+\.\d+\.\d+/)
end

test 'that it shows an error if port is negative' do
  opt = 'https://127.0.0.1:-1'
  assert_proxxy(opt, stderr: 'invalid argument', success: false)
end

test 'that it shows an error if port is out of range' do
  opt = 'https://127.0.0.1:65536'
  assert_proxxy(opt, stderr: 'invalid argument', success: false)
end

test 'that it shows an error if port is omitted' do
  opt = 'socks5://127.0.0.1'
  assert_proxxy(opt, stderr: 'invalid argument', success: false)
end

test 'that it shows an error if host is omitted' do
  opt = 'https://'
  assert_proxxy(opt, stderr: 'invalid argument', success: false)
end

test 'that it shows an error if the host is invalid' do
  opt = 'https://oiujif:3128'
  assert_proxxy(opt, stderr: 'no acceptor', success: false)
end

test 'that it shows an error if the scheme is unknown' do
  opt = 'xyz://127.0.0.1:3128'
  assert_proxxy(opt, stderr: 'invalid argument', success: false)
end

test 'that it shows an error if host is omitted' do
  opt = 'oiujif'
  assert_proxxy(opt, stderr: 'invalid argument', success: false)
end

test 'that it shows an error if connect timeout is invalid' do
  opt = '--connect-timeout=x'
  assert_proxxy(opt, stderr: 'invalid argument', success: false)
end

test 'that it shows an error if connect timeout is negative' do
  opt = '--connect-timeout=-1.5'
  assert_proxxy(opt, stderr: 'invalid argument', success: false)
end

test 'that it shows an error if port is in use' do
  opt = 'https://127.0.0.1:3128'
  assert_proxxy(opt) do
    assert_proxxy(opt, stderr: 'port is in use', success: false)
  end
end

Server.start_echo_server(port: 3000) do
  # TODO: Disallow proxy requests to localhost by default because it can be insecure
  # TODO: Allow only white-listed hosts? tcp/udp:host:port?
  # TODO: Support socks4 because it's easy?
  # TODO: Limit the number of open connections?
  # TODO: make sure that it works on windows

  path = File.join(Dir.tmpdir, 'proxxy')
  socks5 = "socks5://#{path}"

  def socks5_authenticate(socket)
    # Client: authenticate
    socket.write("\x05\x01\x00")
    # Proxy: authenticated
    assert_equal "\x05\x00", socket.readpartial(2)
  end

  test 'that it suports no auth' do
    assert_proxxy(socks5) { |socket| socks5_authenticate(socket) }
  end

  test 'that it closes connection if socks message is invalid' do
    assert_proxxy(socks5, stdout: /failure/) do |socket|
      # Client: send some garbage
      socket.write("\x03")
      # Connection closed
      assert socket.read.empty?
    end
  end

  test 'that it returns 0xFF if there are no acceptable auth methods' do
    assert_proxxy(socks5, stdout: /failure/) do |socket|
      # Client: authenticate via GSSAPI or username/password
      socket.write("\x05\x02\x01\x02")
      # Proxy: no acceptable methods
      assert_equal "\x05\xFF", socket.readpartial(2)
    end
  end

  test 'that it returns 0xFF if nmethods is zero' do
    assert_proxxy(socks5, stdout: /failure/) do |socket|
      # Client: offer no authentication methods
      socket.write("\x05\x00")
      # Proxy: no acceptable methods
      assert_equal "\x05\xFF", socket.readpartial(2)
    end
  end

  test 'that it ignores extra data' do
    assert_proxxy(socks5, stdout: /failure/) do |socket|
      # Client: authenticate via GSSAPI (appends some garbage data)
      socket.write("\x05\x01\x01\x00")
      # Proxy: no acceptable methods
      assert_equal "\x05\xFF", socket.readpartial(2)
    end
  end

  test 'that it returns 0x04 if host is unreachable' do
    assert_proxxy(socks5, stdout: /failure/) do |socket|
      socks5_authenticate(socket)
      # Client: connect to @oiujif:3000
      socket.write("\x05\x01\x00\x03\x07@oiujif\x0B\xB8")
      # Proxy: host unreachable
      assert_equal "\x05\x04\x00\x01\x00\x00\x00\x00\x00\x00", socket.gets
    end
  end

  test 'that it returns 0x05 if connection is refused' do
    assert_proxxy(socks5, stdout: /failure/) do |socket|
      socks5_authenticate(socket)
      # Client: connect to 127.0.0.1:3001
      socket.write("\x05\x01\x00\x01\x7F\x00\x00\x01\x0B\xB9")
      # Proxy: connection refused
      assert_equal "\x05\x05\x00\x01\x00\x00\x00\x00\x00\x00", socket.gets
    end
  end

  test 'that it returns 0x07 if command is not supported' do
    assert_proxxy(socks5, stdout: /failure/) do |socket|
      socks5_authenticate(socket)
      # Client: send undefined command (0x04)
      socket.write("\x05\x04\x00\x01\x7F\x00\x00\x01\x0B\xB8")
      # Proxy: command not supported
      assert_equal "\x05\x07\x00\x01\x00\x00\x00\x00\x00\x00", socket.gets
    end
  end

  test 'that it returns 0x08 if address type is not supported' do
    assert_proxxy(socks5, stdout: /failure/) do |socket|
      socks5_authenticate(socket)
      # Client: send undefined address type (0x02)
      socket.write("\x05\x01\x00\x02\x00\x00\x00\x00\x00\x00")
      # Proxy: address type not supported
      assert_equal "\x05\x08\x00\x01\x00\x00\x00\x00\x00\x00", socket.gets
    end
  end

  test 'that it returns 0x04 if connection times out' do
    Server.start_dead_server(port: 3001) do
      opts = %w[--connect-timeout 0.05]
      assert_proxxy(socks5, *opts, stdout: /failure/) do |socket|
        socks5_authenticate(socket)
        # Client: connect to 127.0.0.1:3001
        socket.write("\x05\x01\x00\x01\x7F\x00\x00\x01\x0B\xB9")
        # Proxy: host unreachable
        assert_equal "\x05\x04\x00\x01\x00\x00\x00\x00\x00\x00", socket.gets
      end
    end
  end

  address_types = %w[ipv4 domain ipv6]

  test_p 'that it supports connect command: %s', address_types do |type|
    assert_proxxy(socks5, stdout: /success/) do |socket|
      socks5_authenticate(socket)
      case type
      when 'ipv4'
        # Client: connect to 127.0.0.1:3000
        socket.write("\x05\x01\x00\x01\x7F\x00\x00\x01\x0B\xB8")
        # Proxy: connected
        assert_equal "\x05\x00\x00\x01\x7F\x00\x00\x01", socket.readpartial(8)
      when 'domain'
        # Client: connect to localhost:3000
        socket.write("\x05\x01\x00\x03\x09localhost\x0B\xB8")
        # Proxy: connected
        assert_equal "\x05\x00\x00\x04" + "\x00" * 15 + "\x01", socket.readpartial(20)
      when 'ipv6'
        # Client: connect to [::1]:3000
        socket.write("\x05\x01\x00\x04" + "\x00" * 15 + "\x01\x0B\xB8")
        # Proxy: connected
        assert_equal "\x05\x00\x00\x04" + "\x00" * 15 + "\x01", socket.readpartial(20)
      else
        assert false, type
      end
      _bind_port = socket.readpartial(2)
      # Client: send some data
      socket.write('proxxy')
      # Client: receive the same data from the server
      assert_equal 'proxxy', socket.readpartial(7)
    end
  end

  test_p 'that it can handle slow clients: %s', address_types do |type|
    assert_proxxy(socks5, stdout: /success/) do |socket|
      # Client: send a part of authentication request
      socket.write("\x05")
      socket.flush
      sleep(0.05)
      # Client: send the next part of the request
      socket.write("\x02\x01")
      socket.flush
      sleep(0.05)
      # Client: send the rest of the request
      socket.write("\x00")
      # Proxy: authenticated
      _reply = socket.readpartial(2)
      # Client: send a part of connect request
      socket.write("\x05\x01\x00")
      socket.flush
      sleep(0.05)
      case type
      when 'ipv4'
        # Client: send another part of the request
        socket.write("\x01\x7F\x00\x00\x01\x0B")
      when 'domain'
        # Client: send another part of the request
        socket.write("\x03\x09localhost\x0B")
      when 'ipv6'
        # Client: send another part of the request
        socket.write("\x04" + "\x00" * 15 + "\x01\x0B")
      else
        assert false, type
      end
      socket.flush
      sleep(0.05)
      # Client: send the rest of the request
      socket.write("\xB8")
      # Proxy: connected
      _reply = socket.readpartial(8)
    end
  end

  test 'that it supports IPv6' do
    assert_proxxy('https://[::1]:3128', &:close)
  end

  test 'that it supports bind command' do
    assert_proxxy(socks5) do |socks|
      socks5_authenticate(socks)
      # Client: listen for connection from 127.0.0.1
      socks.write("\x05\x02\x00\x01\x7F\x00\x00\x01\x0B\xB8")
      # Proxy: listening on 127.0.0.1
      assert_equal "\x05\x00\x00\x01\x7F\x00\x00\x01", socks.readpartial(8)
      port = socks.readpartial(2).unpack1('n')
      # Server: connect to the proxy
      TCPSocket.open('127.0.0.1', port) do |server|
        # Proxy: server 127.0.0.1 connected
        assert_equal "\x05\x00\x00\x01\x7F\x00\x00\x01", socks.readpartial(8)
        server_port = socks.readpartial(2).unpack1('n')
        assert_equal server.local_address.ip_port, server_port
        begin
          # Server: try to connect to the proxy again
          TCPSocket.open('127.0.0.1', port) { assert false, 'connected twice' }
        rescue Errno::ECONNREFUSED
          # Proxy: only one server connection is allowed
        end
        # Server: send some data
        server.write('proxxy')
        # Client: received the data
        assert_equal 'proxxy', socks.readpartial(7)
      end
    end
  end

  test 'that it rejects bind commands with domain names' do
    assert_proxxy(socks5, stdout: /failure/) do |socket|
      socks5_authenticate(socket)
      # Client: listen for connection from localhost
      socket.write("\x05\x02\x00\x03\x09localhost\x0B\xB8")
      # Proxy: address type not supported
      assert_equal "\x05\x08\x00\x01\x00\x00\x00\x00\x00\x00", socket.gets
    end
  end

  test 'that it returns 0x03 if it cannot find appropriate ifaddr' do
    assert_proxxy(socks5, stdout: /failure/) do |socket|
      socks5_authenticate(socket)
      # Client: listen for connection from @oiujif
      socket.write("\x05\x02\x00\x01\x00\x00\x00\x00\x0B\xB8")
      # Proxy: network unreachable
      assert_equal "\x05\x03\x00\x01\x00\x00\x00\x00\x00\x00", socket.gets
    end
  end

  test_p 'that it supports udp associaton: %s', %i[ipv4 ipv6] do |type|
    case type
    when :ipv4
      addr = IPAddr.new('127.0.0.1')
      addrn = "\x01#{addr.hton}"
      reply_addrn = "\x00\x00\x00\x01#{addr.mask(0).hton}"
    when :ipv6
      addr = IPAddr.new('::1')
      addrn = "\x04#{addr.hton}"
      reply_addrn = "\x00\x00\x00\x04#{addr.mask(0).hton}"
    end
    assert_proxxy(socks5) do |socks|
      socks5_authenticate(socks)
      # Client: udp associate from :4000
      socks.write("\x05\x03\x00#{addrn}\x0F\xA0")
      # Proxy: listening on ...
      assert_equal "\x05\x00\x00#{addrn}", socks.readpartial(3 + addrn.bytesize)
      port = socks.readpartial(2).unpack1('n')
      UDPSocket.open(addr.family) do |relay|
        # Client: send "proxxy" to :3002
        msg = "\x00\x00\x00#{addrn}\x0B\xBAproxxy"
        relay.bind(addr.to_s, 4001)
        relay.send(msg, 0, addr.to_s, port)
        # Relay: not allowed (port mismatch)
        assert "\x05\x02", relay.readpartial(2)
      end
      Server.start_udp_echo_server(port: 3002) do
        UDPSocket.open(addr.family) do |relay|
          # Client: send "proxxy" to :3002
          msg = "\x00\x00\x00#{addrn}\x0B\xBAproxxy"
          relay.bind(addr.to_s, 4000)
          relay.send(msg, 0, addr.to_s, port)
          # Relay: received "proxxy" from the server
          reply = relay.readpartial(64)
          assert reply.start_with?(reply_addrn), reply.inspect
          assert reply.end_with?('proxxy'), reply.inspect
        end
      end
    end
  end

  test 'that it rejects udp associate commands with domain names' do
    assert_proxxy(socks5, stdout: /failure/) do |socket|
      socks5_authenticate(socket)
      # Client: udp associate from localhost
      socket.write("\x05\x03\x00\x03\x09localhost\x0B\xB8")
      # Proxy: address type not supported
      assert_equal "\x05\x08\x00\x01\x00\x00\x00\x00\x00\x00", socket.gets
    end
  end

  test 'that it accepts only one socks5 command' do
    assert_proxxy(socks5, stdout: /failure/) do |socket|
      socks5_authenticate(socket)
      # Client: listen for connection from 127.0.0.1
      socket.write("\x05\x02\x00\x01\x7F\x00\x00\x01\x0B\xB8")
      socket.readpartial(10)
      # Client: same command again
      socket.write("\x05\x02\x00\x01\x7F\x00\x00\x01\x0B\xB8")
      # Proxy: failure
      assert socket.read.empty?
    end
  end

  test 'that it ignores all incomming data after a failure' do
    # TODO: ONly one match
    assert_proxxy(socks5, stdout: /failure/) do |socket|
      # Client: send 1 MiB of garbage
      socket.write('x' * 2**20) rescue SystemCallError
      # Proxy: failure
      assert socket.read.empty?
    end
  end

  test 'that it can tunnel data' do
    assert_proxxy(stdout: /success/) do |socket|
      socket.write("CONNECT 127.0.0.1:3000 HTTP/1.1\r\n\r\n")

      assert_equal "HTTP/1.1 200 Connection established\r\n", socket.gets
      assert_equal "\r\n", socket.gets

      socket.write("proxxy\r\n")
      assert_equal "proxxy\r\n", socket.gets
    end
  end

  test 'that it supports data pipelining' do
    assert_proxxy(stdout: /success/) do |socket|
      socket.write("CONNECT 127.0.0.1:3000 HTTP/1.1\r\n\r\nproxxy\r\n")

      assert_equal "HTTP/1.1 200 Connection established\r\n", socket.gets
      assert_equal "\r\n", socket.gets
      assert_equal "proxxy\r\n", socket.gets
    end
  end

  test 'that it handles slow clients' do
    assert_proxxy(stdout: /success/) do |socket|
      socket.write("CONNECT 127.0.0.1:3000 HTTP/1.1\r\n")
      socket.flush
      sleep(0.05)
      socket.write("\r\n")

      assert_equal "HTTP/1.1 200 Connection established\r\n", socket.gets
      assert_equal "\r\n", socket.gets
    end
  end

  test 'that it can listen on tcp port' do
    opt = 'https://127.0.0.1:3128'
    assert_proxxy(opt, stdout: /success/) do |socket|
      socket.write("CONNECT 127.0.0.1:3000 HTTP/1.1\r\n\r\n")

      assert_equal "HTTP/1.1 200 Connection established\r\n", socket.gets
      assert_equal "\r\n", socket.gets
    end
  end

  test 'that it can disable logging' do
    assert_proxxy('--quiet') do |socket|
      socket.write("CONNECT 127.0.0.1:3000 HTTP/1.1\r\n\r\n")
      socket.gets
    end
  end

  test 'that CRs are optional' do
    assert_proxxy(stdout: /success/) do |socket|
      socket.write("CONNECT 127.0.0.1:3000 HTTP/1.1\n\n")

      assert_equal "HTTP/1.1 200 Connection established\r\n", socket.gets
    end
  end

  test 'that it allows headers in proxy requests' do
    assert_proxxy(stdout: /success/) do |socket|
      socket.write(
        "CONNECT 127.0.0.1:3000 HTTP/1.1\r\n" \
        "Host: 127.0.0.1:3000\r\n\r\n"
      )

      assert_equal "HTTP/1.1 200 Connection established\r\n", socket.gets
    end
  end

  test 'that it handles clients that disconnect without sending any data' do
    assert_proxxy(&:close)
  end

  test 'that it handles clients that disconnect before receiving 200 OK' do
    Server.start_dead_server(port: 3001) do
      assert_proxxy(stdout: /success 0/) do |socket|
        socket.write("CONNECT 127.0.0.1:3001 HTTP/1.1\r\n\r\n")
        sleep(0.05)
      end
    end
  end

  test 'that it can be chained' do
    assert_proxxy('https://127.0.0.1:3128', stdout: /success/) do |socket|
      socket.write("CONNECT 127.0.0.1:3128 HTTP/1.1\r\n\r\n")
      socket.readpartial(64)
      socket.write("CONNECT 127.0.0.1:3000 HTTP/1.1\r\n\r\n")
      socket.readpartial(64)
      socket.write("proxxy\r\n")
      assert_equal "proxxy\r\n", socket.gets
    end
  end

  test 'that it closes connection if it cannot connect to the server' do
    assert_proxxy(stdout: /failure/) do |socket|
      socket.write("CONNECT 127.0.0.1:3001 HTTP/1.1\r\n\r\n")

      assert socket.read.empty?
    end
  end

  test 'that it closes connection if proxy request is invalid' do
    assert_proxxy(stdout: /failure/) do |socket|
      socket.write("x\r\n\r\n")

      assert socket.read.empty?
    end
  end

  test 'that it closes connection if the server hostname is invalid' do
    assert_proxxy(stdout: /failure/) do |socket|
      socket.write("CONNECT @oiujif:3000 HTTP/1.1\r\n\r\n")

      assert socket.read.empty?
    end
  end

  test 'that it closes connection if the server port is too high' do
    assert_proxxy(stdout: /failure/) do |socket|
      socket.write("CONNECT 127.0.0.1:2147483648 HTTP/1.1\r\n\r\n")

      assert socket.read.empty?
    end
  end

  test 'that it closes connection if the server port starts with 0' do
    assert_proxxy(stdout: /failure/) do |socket|
      socket.write("CONNECT 127.0.0.1:09 HTTP/1.1\r\n\r\n")

      assert socket.read.empty?
    end
  end
end
