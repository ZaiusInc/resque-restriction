require 'spec_helper'

module Resque
  module Plugins
    module Restriction
      RSpec.describe ConcurrencyLimiter do
        KEY = 'limiter_test'.freeze

        before(:suite) do
          Resque.redis.flushall
        end

        after(:each) do
          Resque.redis.flushall
        end

        it 'limits concurrency' do
          limiter1 = ConcurrencyLimiter.new(Resque.redis)
          limiter2 = ConcurrencyLimiter.new(Resque.redis)
          limiter3 = ConcurrencyLimiter.new(Resque.redis)

          expect(limiter1.try_start(KEY, 2)).to be_truthy
          expect(limiter2.try_start(KEY, 2)).to be_truthy
          expect(limiter3.try_start(KEY, 2)).to be_falsey
          expect(Resque.redis.zcard(KEY)).to eq(2)

          limiter1.finish(KEY)
          limiter2.finish(KEY)
          expect(Resque.redis.zcard(KEY)).to eq(0)
        end

        it 'limits concurrency across multiple keys' do
          KEY2 = [KEY, 'foo'].join(':')
          limiter1 = ConcurrencyLimiter.new(Resque.redis)
          limiter2 = ConcurrencyLimiter.new(Resque.redis)
          limiter3 = ConcurrencyLimiter.new(Resque.redis)

          expect(limiter1.try_start(KEY, 1)).to be_truthy
          expect(limiter2.try_start(KEY2, 1)).to be_truthy
          expect(limiter3.try_start(KEY, 1)).to be_falsey
          expect(limiter3.try_start(KEY2, 1)).to be_falsey
          expect(Resque.redis.zcard(KEY)).to eq(1)
          expect(Resque.redis.zcard(KEY2)).to eq(1)

          limiter1.finish(KEY)
          limiter2.finish(KEY2)
          expect(Resque.redis.zcard(KEY)).to eq(0)
          expect(Resque.redis.zcard(KEY2)).to eq(0)
        end

        it 'determines if concurrency would be limited' do
          limiter1 = ConcurrencyLimiter.new(Resque.redis)
          limiter2 = ConcurrencyLimiter.new(Resque.redis)

          expect(limiter1.try_start(KEY, 1)).to be_truthy
          expect(limiter2.can_start?(KEY, 1)).to be_falsey
          expect(limiter2.can_start?(KEY, 2)).to be_truthy

          limiter1.finish(KEY)
        end

        it 'kills the heartbeat thread' do
          limiter1 = ConcurrencyLimiter.new(Resque.redis)

          expect(limiter1.try_start(KEY, 1)).to be_truthy

          thread = limiter1.instance_variable_get(:@thread)
          expect(thread.alive?).to be_truthy

          limiter1.finish(KEY)
          expect(thread.alive?).to be_falsey
          expect(limiter1.instance_variable_get(:@thread)).to be_nil
        end

        it 'has no negative side-effects if finish is called without start' do
          limiter1 = ConcurrencyLimiter.new(Resque.redis)

          limiter1.finish(KEY)
          expect(Resque.redis.exists(KEY)).to be_falsey

          expect(limiter1.try_start(KEY, 1)).to be_truthy

          limiter1.finish(KEY)
          limiter1.finish(KEY)
          expect(Resque.redis.zcard(KEY)).to eq(0)
        end

        it 'refreshes the lock over time' do
          limiter = ConcurrencyLimiter.new(Resque.redis)

          # mock time so we can time-travel
          mock_time = 1593719580
          allow(Time).to receive(:now) { Time.at(mock_time) }
          ConcurrencyLimiter.const_set(:CONCURRENT_HEARTBEAT, 0) # fast-forward heartbeat

          expect(limiter.try_start(KEY, 1)).to be_truthy
          expect(Resque.redis.zcard(KEY)).to eq(1)

          job_id = Resque.redis.get(ConcurrencyLimiter::JOB_ID_KEY)
          expect(Resque.redis.zscore(KEY, job_id)).to eq(mock_time)

          mock_time += 15
          sleep(0.01) # yield to heartbeat thread
          expect(Resque.redis.zscore(KEY, job_id)).to eq(mock_time)

          limiter.finish(KEY)
        end

        it 'ignores and removes stale locks' do
          limiter = ConcurrencyLimiter.new(Resque.redis)

          # mock time so we can time-travel
          mock_time = 1593719580
          allow(Time).to receive(:now) { Time.at(mock_time) }
          # engage infinite improbability drive (make this the 1 in a hundred chance every time)
          allow(limiter).to receive(:rand).and_return(0)

          # insert a stale member
          Resque.redis.zadd(KEY, 0, mock_time - 76)

          expect(limiter.try_start(KEY, 1)).to be_truthy
          expect(Resque.redis.zcard(KEY)).to eq(2)

          sleep(0.01) # yield to heartbeat thread

          limiter.finish(KEY)
          expect(Resque.redis.zcard(KEY)).to eq(0)
        end
      end
    end
  end
end
