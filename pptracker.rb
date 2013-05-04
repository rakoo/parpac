require 'reel'
require 'cgi'
require 'bencode'

# Monkey-patch to add .bencode to Set
class Set
  def bencode
    self.to_a.bencode
  end
end

class NilClass
  def bencode
    "0:"
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

      if request.uri.path == "/announce"
        query_hash = CGI.parse(request.query_string).inject({}) do |acc, el|
          # all params are unique
          acc.merge({el[0] => el[1].first})
        end
        response = Celluloid::Actor[:datastore].future.process query_hash

        request.respond response.value[:status], response.value[:body].bencode
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

    # A map from package_hash to info_hashes
    # each info_hash has the number of announced peers associated to it
    @phash2ihash = {}

    # A map of when peers where last active.
    # Key is peer_id-info_hash, value is time in seconds since UNIX
    # epoch
    @touched = {}

    async.start_degrading_loop
  end

  def start_degrading_loop
    every(60) do
      now = Time.now.to_i
      @touched.each do |peerid_ihash, touched|
        @touched.delete(peerid_ihash) if (now < touched or now - touched > 60)
      end
    end
  end

  def process query_hash
    # Don't honor compact param, because it's IPv4 only
    # Don't honor key param, there is no auth in here
    # Don't honor trackerid param

    peer_id = query_hash["peer_id"]
    return bad_request("Bad peer_id") unless peer_id.size == 20

    phash = query_hash["package_hash"]
    return bad_request("Bad package_hash") if phash and phash.size != 20

    ihash = query_hash["info_hash"]
    return bad_request("Bad info_hash") if ihash and ihash.size != 20

    if phash and ihash
      @phash2ihash[phash] ||= {}
      @phash2ihash[phash][ihash] ||= 0
      @phash2ihash[phash][ihash] += 1
    end

    best_ihash = ihash || best_in_propositions(phash)
    return {status: :not_found, body: {failure_reason: "not serving this package"}} unless best_ihash

    @swarms[best_ihash] ||= {}
    swarm = @swarms[best_ihash]

    # Don't record starting/in-progress dls, only complete ones
    swarm[:complete] ||= 0
    swarm[:complete] += 1 if query_hash["event"] == "completed"

    swarm[:peers] ||= {}
    if existing_peer = swarm[:peers][query_hash["peer_id"]] and query_hash["event"] == "stopped"
      swarm[:peers].delete(existing_peer)
      swarm[:complete] -= 1
    else
      new_peer = {
        peer_id: query_hash["peer_id"],
        ip: query_hash["ip"],
        port: query_hash["port"],
      }
      swarm[:peers][new_peer[:peer_id]] = new_peer
    end
    
    @touched["#{query_hash["peer_id"]}}-#{best_ihash}"] = Time.now.to_i

    body = {
      interval: 60,
      complete: swarm[:complete],
      incomplete: 0,
    }

    unless query_hash["no_peer_id"] == "1"
      p swarm[:peers].values
      body.merge({ peers: swarm[:peers].values })
    end


    p body
    {status: :ok, body: body}
  end

  # Pick the most announced ihash for this package_hash
  def best_in_propositions package_hash
    return nil unless @phash2ihash[package_hash]

    @phash2ihash[package_hash].inject({}) do |acc, el|
      if acc == {}
        el
      elsif acc[:count] < el.values.first
        {ihash: el.keys.first, count: el.values.first}
      end
    end[:ihash]
  end

  private

  def bad_request reason
    {status: :bad_request, body: {"failure reason" => reason}}
  end

end

if __FILE__ == $0
  TrackerServer.new
  DataStore.supervise_as :datastore

  sleep
end
