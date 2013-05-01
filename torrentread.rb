#!/usr/bin/env ruby

require 'trollop'
require 'bencode'
require 'base64'

def indent_str str, offset=0, special=false
  if str.respond_to? :each_pair
    str.each_pair do |k,v|
      offset.times {print "\t"}
      puts "#{k} =>"
      special = (k == 'pieces' ? true : false)
      puts indent_str v, offset+1, special
    end
  else
    offset.times {print "\t"}
    if special
      puts Base64.encode64(str)
    else
      puts str
    end
  end
end

opts = Trollop::options do
  opt :file, "The torrent file", :type => :string
  opt :filespath, "torrent files path", :type => :string
end

if opts[:file]
  puts BEncode.load_file(opts[:file])
elsif opts[:filespath]
  Dir.entries(opts[:filespath]).each do |filename|
    if filename == '.' or filename == '..'
      next
    end
    data = BEncode.load_file(File.join(opts[:filespath], filename))
    puts "#{data["info"]["pieces"].size / 20}\t#{filename}"
  end
end
