module ParPac
  class FileReader
    include Celluloid::IO

    def initialize filename
      @file = File.open(filename, 'r')
    end

    def read offset, length
      @file.seek offset
      @file.read length
    end
  end
end
