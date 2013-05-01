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

  class Message

    def initialize cmd, payload = nil
      @cmd = cmd
      @payload = payload
    end

    def self.parse raw_message
      message_size = raw_message[0..3].unpack("N").first
      cmd = raw_message[3].unpack("C").first
      payload = raw_message[4..-1]

      self.new(cmd, payload)
    end

    def cmd
      @cmd
    end

    def to_wire_format
      if @payload
        size = @cmd.to_s.size + @payload.size
        [size, @cmd, @payload].pack("NCa")
      else
        size = @cmd.to_s.size
        [size, @cmd].pack("NC")
      end
    end

  end
end
