#!/usr/bin/env ruby

require 'trollop'
require 'socket'
require 'digest/sha1'
require 'cgi'
require 'bencode'

def to_hex bin
  bin.each_byte.map{|byte| byte.to_s(16)}.join
end

opts = Trollop::options do
  opt :peer, "peer to connect to in 0.0.0.0:1234 format", :type => :string
  opt :file, "torrent file to use", :type => :string
end

peer = opts[:peer]
torrent = opts[:file]
abort("no peer!") unless peer
abort("no torrent!") unless torrent

host, port = peer.split(':')

decoded = BEncode.load_file(torrent)
info_hash = Digest::SHA1.digest(BEncode.dump(decoded["info"]))
peer_id = Digest::SHA1.digest(Time.now.to_s + "a")

handshake = [19].pack("C")
handshake << "BitTorrent Protocol"
handshake << 8.times.map{0}.pack("C8")
handshake << info_hash
handshake << peer_id

socket = TCPSocket.new(host, port)
puts "sending for info_hash(#{info_hash.unpack("A*")}) with peer_id(#{peer_id.unpack("A*")})"
socket.print handshake

pstrlen = socket.read(1).unpack('C').first
raise StandardError, "pstrlen should be 19, received #{pstrlen}" unless pstrlen.to_i == 19

pstr = socket.read(19)
raise StandardError, "pstr should be \"BitTorent Protocol\", received #{pstr}" unless pstr == "BitTorrent Protocol"

reserved = socket.read(8)
puts "; reserved bits: #{reserved.unpack('c8')}"

info_hash = socket.read(20)
puts "; info_hash: #{to_hex(info_hash)}"

peer_id = socket.read(20)
puts "; peer_id: #{to_hex(peer_id)}"

# handshake
received = []
while data = socket.readpartial(4)
  puts "; received #{data.size} bytes"
  break if data.size == 0
  message_size = data.unpack("N").first
  puts "\t; message is #{message_size} bytes long"

  message = socket.readpartial(message_size)
  break if message.size == 0

  cmd, payload = message.unpack("Ca*")
  puts "\t; cmd: #{cmd}"
  received << cmd
  puts "\t; payload: #{payload[0..10].inspect}"

  break if received.include?(1) and received.include?(3) and received.include?(5)
end

# ok, now the retrieve
request_msg = "\6"
request_msg << "\0\0\0\0" # index
request_msg << "\0\0\0\0" # begin
request_msg << "\0\0\x3F\xFF"  # length
socket.print "\0\0\0\xd" + request_msg

socket.close
