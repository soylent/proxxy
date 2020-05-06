# frozen_string_literal: true

require_relative 'helper'

test 'that it checks options' do
  assert_proxxxy('--oiujif', stderr: 'invalid option', success: false)
end

test 'that it shows help' do
  assert_proxxxy('--help', stdout: 'Usage:')
end

test 'that it shows version' do
  assert_proxxxy('--version', stdout: /\A\d+\.\d+\.\d+/)
end

test 'that it shows an error if the port is in use' do
  opts = ['--host', '127.0.0.1', '--port', '3128']
  assert_proxxxy(*opts) do
    assert_proxxxy(*opts, stderr: 'port is in use', success: false)
  end
end

test 'that it shows an error if the port is out of range' do
  assert_proxxxy('--port', '-1', stderr: 'invalid argument', success: false)
  assert_proxxxy('--port', '65536', stderr: 'invalid argument', success: false)
end

test 'that it shows an error if the host is invalid' do
  assert_proxxxy('--host', 'oiujif', stderr: 'no acceptor', success: false)
end

test 'that it disallows --host and --socket' do
  opts = ['--host', '127.0.0.1', '--socket', 'sock']

  assert_proxxxy(*opts, stderr: 'mutually exclusive', success: false)
end

test 'that it disallows --port and --socket' do
  opts = ['--port', '3128', '--socket', 'sock']

  assert_proxxxy(*opts, stderr: 'mutually exclusive', success: false)
end

echo = start_echo_server(port: 3000)

begin
  test 'that it can tunnel data' do
    assert_proxxxy(stdout: /success/) do |socket|
      socket.write("CONNECT 127.0.0.1:3000 HTTP/1.1\r\n\r\n")

      assert_equal "HTTP/1.1 200 Connection established\r\n", socket.gets
      assert_equal "\r\n", socket.gets

      socket.puts('proxxxy')

      assert_equal "proxxxy\n", socket.gets
    end
  end

  test 'that it supports data pipelining' do
    assert_proxxxy(stdout: /success/) do |socket|
      socket.write("CONNECT 127.0.0.1:3000 HTTP/1.1\r\n\r\nproxxxy\n")

      assert_equal "HTTP/1.1 200 Connection established\r\n", socket.gets
      assert_equal "\r\n", socket.gets
      assert_equal "proxxxy\n", socket.gets
    end
  end

  test 'that it handles slow clients' do
    assert_proxxxy(stdout: /success/) do |socket|
      socket.write("CONNECT 127.0.0.1:3000 HTTP/1.1\r\n")
      socket.flush
      sleep(0.05)
      socket.write("\r\n")

      assert_equal "HTTP/1.1 200 Connection established\r\n", socket.gets
      assert_equal "\r\n", socket.gets
    end
  end

  test 'that it can listen on tcp port' do
    opts = ['--host', '127.0.0.1', '--port', '3128']
    assert_proxxxy(*opts, stdout: /success/) do |socket|
      socket.write("CONNECT 127.0.0.1:3000 HTTP/1.1\r\n\r\n")

      assert_equal "HTTP/1.1 200 Connection established\r\n", socket.gets
      assert_equal "\r\n", socket.gets
    end
  end

  test 'that it can disable logging' do
    assert_proxxxy('--quiet') do |socket|
      socket.write("CONNECT 127.0.0.1:3000 HTTP/1.1\r\n\r\n")
      socket.gets
    end
  end

  test 'that CRs are optional' do
    assert_proxxxy(stdout: /success/) do |socket|
      socket.write("CONNECT 127.0.0.1:3000 HTTP/1.1\n\n")

      assert_equal "HTTP/1.1 200 Connection established\r\n", socket.gets
    end
  end

  test 'that it allows headers in proxy requests' do
    assert_proxxxy(stdout: /success/) do |socket|
      socket.write(
        "CONNECT 127.0.0.1:3000 HTTP/1.1\r\n" \
        "Host: 127.0.0.1:3000\r\n\r\n"
      )

      assert_equal "HTTP/1.1 200 Connection established\r\n", socket.gets
    end
  end

  test 'that it handles clients that disconnect without sending any data' do
    assert_proxxxy(&:close)
  end

  test 'that it handles clients that disconnect before receiving 200 OK' do
    start_dead_server(port: 3001) do
      assert_proxxxy(stdout: /success 0/) do |socket|
        socket.write("CONNECT 127.0.0.1:3001 HTTP/1.1\r\n\r\n")
        sleep(0.05)
      end
    end
  end

  test 'that it closes connection if it cannot connect to the server' do
    assert_proxxxy(stdout: /failure/) do |socket|
      socket.write("CONNECT 127.0.0.1:3001 HTTP/1.1\r\n\r\n")

      assert socket.read.empty?
    end
  end

  test 'that it closes connection if proxy request is invalid' do
    assert_proxxxy(stdout: /failure/) do |socket|
      socket.write("x\r\n\r\n")

      assert socket.read.empty?
    end
  end

  test 'that it closes connection if the server hostname is invalid' do
    assert_proxxxy(stdout: /failure/) do |socket|
      socket.write("CONNECT @oiujif:3000 HTTP/1.1\r\n\r\n")

      assert socket.read.empty?
    end
  end

  test 'that it closes connection if the server port is too large' do
    assert_proxxxy(stdout: /failure/) do |socket|
      socket.write("CONNECT 127.0.0.1:2147483648 HTTP/1.1\r\n\r\n")

      assert socket.read.empty?
    end
  end

  test 'that it closes connection if the server port starts with 0' do
    assert_proxxxy(stdout: /failure/) do |socket|
      socket.write("CONNECT 127.0.0.1:09 HTTP/1.1\r\n\r\n")

      assert socket.read.empty?
    end
  end
ensure
  echo.kill
end
