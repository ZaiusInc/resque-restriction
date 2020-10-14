require 'spec_helper'

module Resque
  module Restriction
    RSpec.describe Config do
      it 'has a default value for max_queue_peek' do
        expect(Restriction.config.max_queue_peek).to eq(100)
      end

      it 'can be configured with new values' do
        Restriction.configure do |config|
          config.max_queue_peek = 50
        end
        expect(Restriction.config.max_queue_peek).to eq(50)
      end
    end
  end
end
