#!/usr/bin/env ruby

require 'trollop'
require 'socket'
require 'digest/sha1'
require 'cgi'

def to_hex bin
  bin.each_byte.map{|byte| byte.to_s(16)}.join
end

opts = Trollop::options do
  opt :peer, "peer to connect to in 0.0.0.0:1234 format", :type => :string
end

peer = opts[:peer]
abort("no peer!") unless peer

host, port = peer.split(':')

info_hash = Digest::SHA1.digest(Time.now.to_s)
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

while data = socket.readpartial(4)
  puts "; received #{data.size} bytes"
  break if data.size == 0
  message_size = data.unpack("N").first
  puts "\t; message is #{message_size} bytes long"

  message = socket.read(message_size)
  break if message.size == 0

  cmd, payload = message.unpack("Ca")
  puts "\t; cmd: #{cmd}"
  puts "\t; payload: #{payload[1..-1].inspect}"
end

socket.close
