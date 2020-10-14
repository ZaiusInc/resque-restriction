module Resque
  module Restriction
    def self.configure
      yield config
    end

    def self.config
      @config ||= Config.new
    end

    class Config
      attr_accessor :max_queue_peek

      def initialize
        @max_queue_peek = 100
      end
    end
  end
end
