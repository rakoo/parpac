require 'celluloid/io'

module ParPac
  class Peer
    include Celluloid

    def initialize socket, info_hash, filename, tdata, peer_id, self_peer_id
      @socket = socket
      @info_hash = info_hash
      @tdata = tdata
      @filename = filename
      @peer_id = peer_id
      @self_peer_id = self_peer_id

      # just for logging/debugging purpose
      _, @port, @host = socket.peeraddr

      respond_handshake
      send_bitfield
      send_unchoke
      send_not_interested

      async.start_listening

      async.reset_timeout
    end

    def close
      @socket.close
      terminate
    end

    private

    ##
    # Start/reset a timeout that will close the connection after 1 minute of
    # inactivity
    #
    # In our use case, we don't want to maintain a seeding connection
    # for more than 1 minute, since the remote peer will have obtained
    # the file anyway
    def reset_timeout
      @timer = after(60) {close}
    end

    def start_listening
      while data = @socket.readpartial(4096)
        close if data.size == 0
        process Message.parse(data)
      end
    rescue EOFError
      puts "*** #{@host}:#{@port} disconnected"
      close
    rescue Errno::ECONNRESET
      puts "*** #{@host}:#{@port} disconnected"
      close
    end

    def process message
      case message.cmd
      when HAVE
      when REQUEST
        process_request message
      when CANCEL
        puts "op"


      # We don't care about those
      when CHOKE
      when UNCHOKE
      when INTERESTED
      when NOT_INTERESTED
      when BITFIELD
      when PIECE
      when PORT
        puts "noop"
      end
    end

    def process_request request_message

      file_actor = Celluloid::Actor[@filename.to_sym]
      offset = request_message.index * 32768 + request_message.beginbyte
      block = file_actor.future.read offset, request_message.length

      @socket.print PieceMessage.new(request_message.index, request_message.beginbyte, block.value.bytesize, block.value).to_wire_format
    end

    def respond_handshake
      handshake = [19].pack("C")
      handshake << "BitTorrent Protocol"
      handshake << 8.times.map{0}.pack("C8")
      handshake << @info_hash
      handshake << @peer_id

      @socket.print handshake
    end

    def send_unchoke
      @socket.print Message.new(UNCHOKE).to_wire_format
    end
    
    def send_not_interested
      @socket.print Message.new(NOT_INTERESTED).to_wire_format
    end

    def send_bitfield
      pieces_nbr = @tdata["info"]["pieces"].size / 20
      bitfield = pieces_nbr.times.inject("") {|sum, n| sum << 1}
      @socket.print Message.new(BITFIELD, bitfield).to_wire_format
    end
  end
end
