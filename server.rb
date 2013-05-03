#!/usr/bin/env ruby

require 'celluloid/io'
require 'cgi'
require 'digest/sha1'
require 'trollop'

require 'parpac'

module ParPac
  class ProtocolError < StandardError; end

  class EchoServer
    include Celluloid::IO

    def initialize(host, port, opts)
      puts "*** Starting echo server on #{host}:#{port}"

      # Since we included Celluloid::IO, we're actually making a
      # Celluloid::IO::TCPServer here
      @server = TCPServer.new(host, port)
      @peer_id = Digest::SHA1.digest(Time.now.to_s)
      @filedir = opts[:filedir]
      @datadir = opts[:datadir]

      # hash => filename
      @infohashes = Dir.entries(@datadir).inject({}) do |sum, entry|
        next sum if entry == '.' or entry == '..'
        next sum unless entry.match(/\.torrent$/) # this is pretty weak

        file = File.join(@datadir, entry)
        next sum unless File.file? file

        decoded = BEncode.load_file(file)
        info_hash = Digest::SHA1.digest(BEncode.dump(decoded["info"]))

        sum.merge({info_hash => entry})
      end

      puts "*** Init done, starting run"
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
      torrent_data = BEncode.load_file(File.join(@datadir, @infohashes[info_hash]))

      peer_id = socket.read(20)
      puts "; peer_id: #{peer_id.to_hex}"

      filename = File.join(@filedir, @infohashes[info_hash].sub(/\.torrent$/,''))
      file_actor = Celluloid::Actor[filename.to_sym]
      if file_actor == nil
        FileReader.supervise_as filename.to_sym, filename
        file_actor = Celluloid::Actor[filename.to_sym]
      end

      peer = Peer.new(socket, info_hash, filename, torrent_data, peer_id, @peer_id)
    rescue EOFError
      puts "*** #{host}:#{port} disconnected"
      peer.close
    rescue ProtocolError => e
      puts "; Protocol error from #{host}:#{port} : #{e.message}"
      peer.close
    end

  end
end

if __FILE__ == $0
  opts = Trollop::options do
    opt :filedir, "The directory where your package live, typically /var/cache/pacman/pkg", :default => "/var/cache/pacman/pkg"
    opt :datadir, "The directory for tmp data (torrents, ...)", :default => "/home/rakoo/tmp/pacman"
  end

  ParPac::EchoServer.new "0.0.0.0", 6881, opts
  sleep
end
