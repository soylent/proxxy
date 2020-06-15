# frozen_string_literal: true

require 'ipaddr'
require 'socket'

require 'proxy'

class SOCKS5 < Proxy
  module C
    VER_SOCKS5 = 5
    ATYP_IPV4 = 1
    ATYP_DOMAIN = 3
    ATYP_IPV6 = 4
    RSV = 0
    CMD_CONNECT = 1
    CMD_BIND = 2
    CMD_UDP = 3
    METH_NOAUTH = 0
    METH_NOACCEPT = 255
    REP_SUCCESS = 0
    REP_NOTALLOWED = 2
    REP_NETUNREACH = 3
    REP_HOSTUNREACH = 4
    REP_CONNREFUSED = 5
    REP_CMDNOTSUPPORTED = 7
    REP_ATYPNOTSUPPORTED = 8
  end
  private_constant :C

  def post_init
    @authenticated = false
    @finalized = false
    @listen_server = nil
    @listen_socket = nil
    @udp_relay = nil
  end

  def receive_message(msg)
    return authenticate(msg) unless @authenticated
    return failure('unexpected message', msg) if @finalized
    req = Message.unpack(msg) || return

    case req.command
    when C::CMD_CONNECT
      connect(req)
    when C::CMD_BIND
      bind(req)
    when C::CMD_UDP
      udp(req)
    else
      raise cmd
    end

    @finalized = true # done
  rescue Message::Error => e
    send_reply(e.code)
    failure(e)
  rescue Message::FatalError => e
    failure(e, msg)
  end

  def unbind
    super
    @listen_socket&.close
    @udp_relay&.close_connection_after_writing
    EventMachine.stop_server(@listen_server) if @listen_server
  end

  private

  def authenticate(msg)
    methods = Message.auth_unpack(msg) || return

    if methods.include?(C::METH_NOAUTH)
      send_data Message.auth_pack(C::METH_NOAUTH)
      @authenticated = true
    else
      send_data Message.auth_pack(C::METH_NOACCEPT)
      log('failure', "no acceptable auth methods: #{methods}")
    end

    true # done
  end

  def connect(req)
    # TODO: Disallow request to localhost unless the client is local
    completion = proxy_to(req.host.to_s, req.port)
    completion.callback do |server|
      send_reply(C::REP_SUCCESS, server.get_sockname)
    end
    completion.errback do |e|
      # TODO: Test Errno::ENETUNREACH
      # Try: 2607:f8b0:4009:0811:0000:0000:0000:2004:443
      if Errno::ENETUNREACH == e
        send_reply(C::REP_NETUNREACH)
      elsif Errno::ETIMEDOUT == e || EventMachine::ConnectionError === e
        send_reply(C::REP_HOSTUNREACH)
      elsif Errno::ECONNREFUSED == e
        send_reply(C::REP_CONNREFUSED)
      else
        # TODO: how to test?
        p e
      end
      failure(e)
    end
  end

  def bind(req)
    addr = Addrinfo.tcp(req.bind_ip, 0)
    # Disable backlog because we expect only a single client
    @listen_socket = addr.listen(0)
    @listen_server = EventMachine.attach_server(@listen_socket) do |server|
      sockaddr = server.get_peername
      _peer_port, peer_ip = Socket.unpack_sockaddr_in(sockaddr)
      if req.host == peer_ip
        # Allow only one connection
        @listen_socket = @listen_socket.close
        send_reply(C::REP_SUCCESS, sockaddr)
        server.proxy_incoming_to(self)
      else
        # TODO: Test? is it reasonable to test?
        server.close
        # TODO: Logging
      end
    end
    send_reply(C::REP_SUCCESS, @listen_socket.getsockname)
  end

  def udp(req)
    @udp_relay = EventMachine.open_datagram_socket(req.bind_ip, 0, UDPRelay, req)
    send_reply(C::REP_SUCCESS, @udp_relay.get_sockname)
  end

  def send_reply(reply, sockaddr = nil)
    send_data Message.pack(reply: reply, sockaddr: sockaddr)
  end

  class UDPRelay < EventMachine::Connection
    class Remote < EventMachine::Connection
      def initialize(proxy_to)
        super
        @proxy_to = proxy_to
      end

      def receive_data(data)
        reply = Message.pack(sockaddr: get_sockname, data: data)
        @proxy_to.send_data(reply)
      end
    end
    private_constant :Remote

    def initialize(req)
      super
      @client_ip = req.host
      @client_port = req.port
      addr = req.address_type == C::ATYP_IPV6 ? '::' : ''
      @socket = EventMachine.open_datagram_socket(addr, 0, Remote, self)
    end

    def receive_data(data)
      # TODO: Test 0.0.0.0 and 0 port
      peer_port, peer_ip = Socket.unpack_sockaddr_in(get_peername)
      ip_ok = @client_ip == '0.0.0.0' || @client_ip == peer_ip
      port_ok = @client_port == 0 || @client_port == peer_port
      if ip_ok && port_ok
        req = Message.unpack(data, udp: true)
        @socket.send_datagram(req.data, req.host.to_s, req.port)
      else
        send_data Message.pack(reply: C::REP_NOTALLOWED)
      end
    end

    def unbind
      @socket.close_connection_after_writing
    end
  end
  private_constant :UDPRelay

  module Message
    FatalError = Class.new(StandardError)

    Error = Class.new(StandardError) do
      attr_reader :code

      def initialize(msg, code)
        super(msg)
        @code = code
      end
    end

    Request = Struct.new(:command, :fragment, :address_type, :host, :port, :data) do
      def bind_ip
        if address_type == C::ATYP_DOMAIN
          raise Error.new("domain names not supported: #{host.inspect}", C::REP_ATYPNOTSUPPORTED)
        end
        Socket.getifaddrs.each do |ia|
          addr = ia.addr
          next unless addr.ip?
          next if addr.ipv6_linklocal?
          net = IPAddr.new(addr.ip_address).mask(ia.netmask.ip_address)
          begin
            return addr.ip_address if net.include?(host)
          rescue IPAddr::InvalidAddressError
            break
          end
        end
        raise Error.new('no ifaddr', C::REP_NETUNREACH)
      end
    end

    def self.auth_pack(method)
      [C::VER_SOCKS5, method].pack('CC')
    end

    def self.auth_unpack(msg)
      version = msg.unpack1('C')
      raise FatalError, 'fatal' unless version == C::VER_SOCKS5
      return if msg.bytesize < 2
      nmethods = msg.unpack1('xC')
      return if nmethods > msg.bytesize - 2
      msg.unpack("x2C#{nmethods}")
    end

    def self.pack(reply: C::RSV, sockaddr: nil, data: nil)
      if sockaddr
        addr = Addrinfo.new(sockaddr)
        if addr.ipv4?
          addr_type = C::ATYP_IPV4
        elsif addr.ipv6?
          addr_type = C::ATYP_IPV6
        else
          raise ArgumentError, addr
        end
        ip = IPAddr.new(addr.ip_address).hton
        port = addr.ip_port
      else
        addr_type = C::ATYP_IPV4
        ip = "\x00\x00\x00\x00"
        port = 0
      end
      version = data ? C::RSV : C::VER_SOCKS5
      [version, reply, C::RSV, addr_type, ip, port, data].pack('C4a*na*')
    end

    def self.unpack(msg, udp: false)
      version = msg.unpack1('C')
      raise FatalError, 'fatal' unless udp || version == C::VER_SOCKS5
      return if msg.bytesize < 5
      cmd, frag, addr_type = msg.unpack('xC3')
      unless udp || cmd == C::CMD_CONNECT || cmd == C::CMD_BIND || cmd == C::CMD_UDP
        raise Error.new("command not supported: #{cmd}", C::REP_CMDNOTSUPPORTED)
      end
      case addr_type
      when C::ATYP_IPV4
        return if msg.bytesize < 10
        host, port, data = msg.unpack('x4a4na*')
        host = IPAddr.new_ntoh(host)
      when C::ATYP_DOMAIN
        len = msg.unpack1('x4C')
        return if msg.bytesize < 7 + len
        host, port, data = msg.unpack("x5a#{len}na*")
      when C::ATYP_IPV6
        return if msg.bytesize < 22
        host, port, data = msg.unpack('x4a16na*')
        host = IPAddr.new_ntoh(host)
      else
        raise Error.new("address type not supported: #{addr_type}", C::REP_ATYPNOTSUPPORTED)
      end
      Request.new(cmd, frag, addr_type, host, port, data)
    end
  end
  private_constant :Message
end
