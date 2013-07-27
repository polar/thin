require 'spec_helper'

if SWIFTIPLY_PATH.empty?
  warn "Ignoring Server on Swiftiply specs, gem install swiftiply to run"
else
  describe Server, 'on Swiftiply' do
    before do
      @swiftiply = fork do
        exec "cd /home/polar/src/swiftiply; bundle exec ruby bin/swiftiply -c #{File.dirname(__FILE__)}/swiftiply.yml"
      end
      @request_number = 0
      #wait_for_socket('0.0.0.0', 3333)
      sleep 2 # HACK ooh boy, I wish I knew how to make those specs more stable...
      start_server('0.0.0.0', 5555, :backend => Backends::SwiftiplyClient, :wait_for_socket => false) do |env|
        @request_number += 1
        headers = { 'Content-Type' => 'text/html' }
        case env["REQUEST_PATH"]
          when "/use_ct"
            body = env.inspect + env['rack.input'].read + "RequestNumber:#{@request_number}"
            headers["Content-Length"] = "#{body.length}"
          when "/"
            body = env.inspect + env['rack.input'].read + "RequestNumber:#{@request_number}"
          else
            body = env.inspect + env['rack.input'].read + "RequestNumber:#{@request_number}"
        end
        [200, headers, body]
      end
    end

    it 'should GET from Net::HTTP content length' do
      Net::HTTP.get(URI.parse("http://0.0.0.0:3333/use_ct?cthis")).should include('cthis')
    end
    
    it 'should GET from Net::HTTP without content length' do
      Net::HTTP.get(URI.parse("http://0.0.0.0:3333/?cthis")).should include('cthis')
    end

    it 'should GET from Net::HTTP and should have consecutive requests from one server' do
      result = Net::HTTP.get(URI.parse("http://0.0.0.0:3333/use_ct"))
      result.should include("RequestNumber:1")
      result = Net::HTTP.get(URI.parse("http://0.0.0.0:3333/use_ct"))
      result.should include("RequestNumber:2")
      result = Net::HTTP.get(URI.parse("http://0.0.0.0:3333/use_ct"))
      result.should include("RequestNumber:3")
    end

    it 'should GET from Net::HTTP and should have consecutive requests from one server without content-length' do
      result = Net::HTTP.get(URI.parse("http://0.0.0.0:3333/"))
      result.should include("RequestNumber:1")
      result = Net::HTTP.get(URI.parse("http://0.0.0.0:3333/"))
      result.should include("RequestNumber:2")
      result = Net::HTTP.get(URI.parse("http://0.0.0.0:3333/"))
      result.should include("RequestNumber:3")
    end
  
    it 'should POST from Net::HTTP' do
      Net::HTTP.post_form(URI.parse("http://0.0.0.0:3333/"), :arg => 'pirate').body.should include('arg=pirate')
    end

    it 'should handle Content-Length' do
      Net::HTTP.post_form(URI.parse("http://0.0.0.0:3333/use_content_length"), :arg => 'pirate').body.should include('arg=pirate')
    end
  
    after do
      stop_server
      Process.kill(9, @swiftiply)
    end
  end
end