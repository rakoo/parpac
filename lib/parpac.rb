require 'parpac/peer'
require 'parpac/message'
require 'parpac/filereader'

require 'bencode'

## Display the hex-encoded version of a stirng
class String
  def to_hex
    self.each_byte.map{|byte| byte.to_s(16)}.join
  end
end

