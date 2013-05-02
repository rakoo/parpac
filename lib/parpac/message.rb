module ParPac

  ## Message types
  CHOKE = 0
  UNCHOKE = 1
  INTERESTED = 2
  NOT_INTERESTED = 3
  HAVE = 4
  BITFIELD = 5
  REQUEST = 6
  PIECE = 7
  CANCEL = 8
  PORT = 9

  class MessageError < StandardError; end

  class Message

    def initialize cmd, payload = nil
      @cmd = cmd
      @payload = payload
    end

    def self.parse raw_message
      message_size = raw_message[0..3].unpack("N").first
      cmd = raw_message[4].unpack("C").first
      payload = raw_message[5..-1]

      raise MessageError, "Message is malformed" if message_size != cmd.to_s.size + payload.size

      case cmd
      when REQUEST
        RequestMessage.parse(payload)
      end
    end

    def cmd
      @cmd
    end

    def to_wire_format
      if @payload
        size = @cmd.to_s.size + @payload.size
        [size, @cmd, @payload].pack("NCa*")
      else
        size = @cmd.to_s.size
        [size, @cmd].pack("NC")
      end
    end

  end

  class RequestMessage < Message

    attr_reader :index, :beginbyte, :length

    def initialize cmd, index, beginbyte, length
      @cmd = cmd
      @index = index
      @beginbyte = beginbyte
      @length = length
    end

    def self.parse(payload)
      index, beginbyte, length = payload.unpack("NNN")
      self.new(REQUEST, index, beginbyte, length)
    end
  end

  class PieceMessage < Message

    def initialize index, beginbyte, length, block
      @cmd = REQUEST
      @index = index
      @beginbyte = beginbyte
      @length = length
      @block = block

      @payload = [index, beginbyte, length, block].pack("NNNa*")
    end

  end

end
