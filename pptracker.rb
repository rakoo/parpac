require 'reel'
require 'cgi'
require 'bencode'

# Monkey-patch to add .bencode to Set
class Set
  def bencode
    self.to_a.bencode
  end
end

class TrackerServer < Reel::Server
  include Celluloid::Logger

  def initialize host = "127.0.0.1", port = 3000
    super(host, port, &method(:on_connection))
  end

  def on_connection connection
    while request = connection.request
      next unless request.is_a?(Reel::Request)
      next unless request.method == "GET"

      if request.url.match '^/announce'
        query_hash = CGI.parse(request.query_string)
        bencoded_body = Celluloid::Actor[:datastore].future.process query_hash

        request.respond :ok, bencoded_body.value

      elsif request.url.match "^/hash/(.{20})\\?#{request.query_string}"
        hashes = Celluloid::Actor[:datastore].future.hashes($1)
        request.respond :ok, hashes.value
      end

      request.close
      connection.close
    end 
  end

end

class DataStore
  include Celluloid::IO
  include Celluloid::Logger

  def initialize
    @swarms = {}
    @phash2ihash = {}

    async.start_degrading_loop
  end

  def start_degrading_loop
    every(60) do
      @swarms.each do |swarm|
      end
    end
  end

  def hashes phash
    @phash2ihash[phash]
  end

  def process query_hash
    # Don't honor compact param, because it's IPv4 only
    # Don't honor key param, there is no auth in here
    # Don't honor trackerid param

    phash = query_hash["package_hash"]
    ihash = query_hash["info_hash"]

    if phash and ihash
      @phash2ihash[phash] ||= {}
      @phash2ihash[phash][ihash] ||= 0
      @phash2ihash[phash][ihash] += 1
    end

    info_hash = query_hash["info_hash"]
    debug info_hash
    if info_hash.nil?
      info_hash = @package_hash_to_info_hash[query_hash["package_hash"]]
    end

    @swarms[query_hash["info_hash"]] ||= {interval: 60}
    swarm = @swarms[query_hash["info_hash"]]

    swarm[:peers] ||= {}
    if existing_peer = swarm[:peers][query_hash["peer_id"]]
      existing_peer[:touched] = Time.now.to_i
    else
      new_peer = {
        peer_id: query_hash["peer_id"],
        ip: query_hash["ip"],
        port: query_hash["port"],
        touched: Time.now.to_i,
      }
      new_peer[:info_hash] = query_hash["info_hash"] if query_hash["info_hash"]
      swarm[:peers][new_peer[:peer_id]] = new_peer
    end

    swarm[:complete] += 1 if query_hash["event"] == "completed"
    swarm[:incomplete] += 1 if query_hash["event"] == "started"

    swarm

    p swarm

    BEncode::dump(swarm)
  end

end

if __FILE__ == $0
  TrackerServer.new
  DataStore.supervise_as :datastore

  sleep
end
