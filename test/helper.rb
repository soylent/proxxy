# frozen_string_literal: true

require 'open3'
require 'socket'
require 'tmpdir'
require 'uri'

def assert_proxxy(*opts, stdout: nil, stderr: nil, success: true, &block)
  if block_given?
    url = opts.find { |opt| !opt.start_with?('-') }
    unless url
      path = File.join(Dir.tmpdir, 'proxxy')
      url = "https://#{path}"
      opts.push(url)
    end
    url = URI.parse(url)
  end
  Open3.popen3('bin/proxxy', *opts) do |_p_stdin, p_stdout, p_stderr, p_thr|
    if block_given?
      retries = 0
      block_success = false
      begin
        if url.host && url.port
          Socket.tcp(url.host.tr('[]', ''), url.port, &block)
        elsif !url.path.empty?
          Socket.unix(url.path, &block)
        else
          raise ArgumentError, url
        end
      rescue Errno::ENOENT, Errno::ECONNREFUSED
        raise if retries > 20
        sleep(0.05)
        retries += 1
        retry
      else
        block_success = true
      ensure
        Process.kill('INT', p_thr[:pid]) rescue Errno::ESRCH

        unless block_success
          puts "\n\n"
          puts "  status: #{p_thr.value}"
          puts "  stdout: #{p_stdout.read}"
          puts "  stderr: #{p_stderr.read}"
        end
      end
    end

    Process.kill('INT', p_thr[:pid]) unless p_thr.join(1)

    err = p_stderr.read
    assert stderr ? err.match?(stderr) : err.empty?, "stderr: #{err}"

    out = p_stdout.read
    assert stdout ? out.match?(stdout) : out.empty?, "stdout: #{out}"

    status = p_thr.value
    assert_equal success, status.success?
  end
end

def test_p(name, params)
  params.each { |param| test(name % param) { yield param } }
end
