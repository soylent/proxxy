# frozen_string_literal: true

require 'open3'
require 'socket'
require 'tmpdir'

def start_echo_server(host: '127.0.0.1', port: 3000)
  queue = Queue.new
  Thread.new do
    TCPServer.open(host, port) do |server|
      queue.push(Thread.current)
      loop do
        socket = server.accept
        IO.copy_stream(socket, socket)
      ensure
        socket&.close
      end
    end
  end
  queue.pop
end

def start_dead_server(host: '127.0.0.1', port: 3001)
  TCPServer.open(host, port) do |server|
    server.listen(0)
    Socket.tcp('127.0.0.1', port) { yield }
  end
end

def assert_proxxxy(*opts, stdout: nil, stderr: nil, success: true, &blk)
  opts.unshift('./proxxxy')

  if block_given?
    port_idx = opts.index('--port') || opts.index('-p')
    port = opts.fetch(port_idx.succ) if port_idx

    unless port
      socket = File.join(Dir.tmpdir, 'proxxxy')
      opts.push('--socket', socket)
    end

    p_stdin, p_stdout, p_stderr, p_thr = Open3.popen3(*opts)

    begin
      if port
        Socket.tcp('127.0.0.1', port, &blk)
      else
        Socket.unix(socket, &blk)
      end
    rescue Errno::ENOENT, Errno::ECONNREFUSED
      sleep 0.01
      retry
    ensure
      Process.kill('INT', p_thr[:pid])

      p_stdin.close

      out = p_stdout.read
      p_stdout.close

      err = p_stderr.read
      p_stderr.close

      status = p_thr.value
    end
  else
    out, err, status = Open3.capture3(*opts)
  end

  stderr_ok = stderr ? err.match?(stderr) : err.empty?
  assert stderr_ok, "stderr: #{err}"

  stdout_ok = stdout ? out.match?(stdout) : out.empty?
  assert stdout_ok, "stdout: #{out}"

  assert_equal success, status.success?
end
