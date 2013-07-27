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
        if @key.nil? || @key == ""
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

    def initialize
      super
    end

    def post_init
      @request  = Request.new
      @response = Thin::SwiftiplyResponse.new
    end

    def connection_completed
      self.comm_inactivity_timeout = 0.0
      send_data swiftiply_handshake(@backend.key)
    end
    
    def persistent?
      true
    end
    
    def unbind
      super
      EventMachine.add_timer(rand(2)) { reconnect(@backend.host, @backend.port) } if @backend.running?
    end

    def post_process_super(result)
      return unless result
      result = result.to_a

      # Status code -1 indicates that we're going to respond later (async).
      return if result.first == AsyncResponse.first

      @response.status, @response.headers, @response.body, @response.packetize = *result

      log "!! Rack application returned nil body. Probably you wanted it to be an empty string?" if @response.body.nil?

      # Make the response persistent if requested by the client
      @response.persistent! if @request.persistent?

      # Send the response
      @response.each do |chunk|
        trace { chunk }
        send_data chunk
      end

    rescue Exception => boom
      puts "#{boom}"
      handle_error
      # Close connection since we can't handle response gracefully
      close_connection
    ensure
      # If the body is being deferred, then terminate afterward.
      if @response.body.respond_to?(:callback) && @response.body.respond_to?(:errback)
        @response.body.callback { terminate_request }
        @response.body.errback  { terminate_request }
      else
        # Don't terminate the response if we're going async.
        terminate_request unless result && result.first == AsyncResponse.first
      end
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
          packetize = true
        else
          packetize = false
        end
      end
      # p status, headers
      post_process_super([status, headers, body, packetize])
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
        puts "terminate_request #{persistent?}"
        unless persistent?
          close_connection_after_writing rescue nil
          close_request_response
        else
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