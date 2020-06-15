# frozen_string_literal: true

require 'proxy'

class HTTPS < Proxy
  def receive_message(msg)
    return unless msg.include?("\r\n\r\n") || msg.include?("\n\n")
    match = msg.match(
      /\ACONNECT ([^:]+):([1-9][0-9]*) (HTTP\/[0-1]\.\d+).*\r?\n\r?\n/m
    )
    if match
      host, port, httpv = match.captures
      completion = proxy_to(host, port)
      completion.callback do |server|
        server.send_data(match.post_match)
        send_data("#{httpv} 200 Connection established\r\n\r\n")
      end
      completion.errback { |e| failure(e) }
    else
      failure("request: #{dump(msg)}")
    end
    true # done
  end
end
