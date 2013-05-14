module Thin
  module Backends
    # Backend to act as a Swiftiply client (http://swiftiply.swiftcore.org).
    class SwiftiplyClient < Base
      attr_accessor :key
      
      attr_accessor :host, :port
      
      def initialize(host, port, options={})
        @host = host
        @port = port.to_i
        @key  = options[:swiftiply].to_s
        if @key.nil? || @key.blank?
          @key = ENV["SWIFTIPLY_KEY"].to_s
        end
        super()
      end

      # Connect the server
      def connect
        EventMachine.connect(@host, @port, SwiftiplyConnection, &method(:initialize_connection))
      end

      # Stops the server
      def disconnect
        EventMachine.stop
      end

      def to_s
        "#{@host}:#{@port} swiftiply"
      end
    end    
  end

  class SwiftiplyConnection < Connection
    def connection_completed
      send_data swiftiply_handshake(@backend.key)
    end
    
    def persistent?
      true
    end
    
    def unbind
      super
      EventMachine.add_timer(rand(2)) { reconnect(@backend.host, @backend.port) } if @backend.running?
    end

    def post_process(result)
      return unless result
      result = result.to_a

      # Status code -1 indicates that we're going to respond later (async).
      return if result.first == AsyncResponse.first
      status, headers, body = *result
      if (status.to_i < 300)
        if !headers.has_key?("Content-Length") || headers["Content-Length"].to_i == 0
          headers["X-Swiftiply-Close"] = "true"
        end
      end
      # p status, headers
      super([status, headers, body])
    end
    
    protected
      def swiftiply_handshake(key)
        'swiftclient' << host_ip.collect { |x| sprintf('%02x', x.to_i)}.join << sprintf('%04x', @backend.port) << sprintf('%02x', key.length) << key
      end
      
      # For some reason Swiftiply request the current host
      def host_ip
        Socket.gethostbyname(@backend.host)[3].unpack('CCCC') rescue [0,0,0,0]
      end

      # Does request and response cleanup (closes open IO streams and
      # deletes created temporary files).
      # Re-initializes response and request if client supports persistent
      # connection.
      def terminate_request
        unless persistent?
          close_connection_after_writing rescue nil
          close_request_response
        else
          send_data "<!--SC->" if @response.headers.has_key?("X-Swiftiply-Close")
          close_request_response
          # Connection become idle but it's still open
          @idle = true
          # Prepare the connection for another request if the client
          # supports HTTP pipelining (persistent connection).
          post_init
        end
      end
  end
end