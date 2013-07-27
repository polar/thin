module Thin
  class SwiftiplyResponse < Response

    attr_accessor :packetize

    def each
      yield head
      if @body.is_a?(String)
        yield "%08d" % @body.length if packetize
        yield @body
      else
        @body.each do |chunk|
          yield "%08d" % chunk.length if packetize
          yield chunk
        end
      end
      yield "--------" if packetize
    end
  end
end