#!/usr/bin/env ruby

require 'celluloid/io'
require 'cgi'
require 'digest/sha1'

require 'parpac'

module ParPac
  class ProtocolError < StandardError; end

  class EchoServer
    include Celluloid::IO

    def initialize(host, port, dir)
      puts "*** Starting echo server on #{host}:#{port}"

      # Since we included Celluloid::IO, we're actually making a
      # Celluloid::IO::TCPServer here
      @server = TCPServer.new(host, port)
      @infohashes = []
      @peer_id = Digest::SHA1.digest(Time.now.to_s)
      @dir = dir
      async.run
    end

    def finalize
      @server.close if @server
    end

    def run
      loop { async.handle_connection @server.accept }
    end

    def handle_connection(socket)
      _, port, host = socket.peeraddr
      puts
      puts "*** Received connection from #{host}:#{port}"

      pstrlen = socket.read(1).unpack('C').first
      raise ProtocolError, "pstrlen should be 19, received #{pstrlen}" unless pstrlen.to_i == 19

      pstr = socket.read(19)
      raise ProtocolError, "pstr should be \"BitTorent Protocol\", received #{pstr}" unless pstr == "BitTorrent Protocol"

      reserved = socket.read(8)
      puts "; reserved bits: #{reserved.unpack('c8')}"

      info_hash = socket.read(20)
      puts "; info_hash: #{info_hash.to_hex}"
      torrent_data = get_torrent_data(info_hash)

      peer_id = socket.read(20)
      puts "; peer_id: #{peer_id.to_hex}"

      peer = Peer.new(socket, info_hash, torrent_data, peer_id, @peer_id)
    rescue EOFError
      puts "*** #{host}:#{port} disconnected"
      peer.close
    rescue ProtocolError => e
      puts "; Protocol error from #{host}:#{port} : #{e.message}"
      peer.close
    end

    def add_managed_infohash infohash
      @infohashes << infohash
    end

    def get_torrent_data info_hash
      BEncode.load_file("#{@dir}/linux-3.8.4-1-x86_64.pkg.tar.xz.torrent")
    end

  end
end

if __FILE__ == $0
  dir = "/home/rakoo/tmp/pacman"
  ParPac::EchoServer.new "0.0.0.0", 9801, dir
  sleep
end
