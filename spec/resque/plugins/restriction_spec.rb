require 'spec_helper'
RSpec.describe Resque::Plugins::Restriction do
  it "should follow the convention" do
    Resque::Plugin.lint(Resque::Plugins::Restriction)
  end

  context "redis_key" do
    it "should get redis_key with different period" do
      expect(MyJob.redis_key(:per_minute)).to eq "restriction:MyJob:#{Time.now.to_i / 60}"
      expect(MyJob.redis_key(:per_hour)).to eq "restriction:MyJob:#{Time.now.to_i / (60*60)}"
      expect(MyJob.redis_key(:per_day)).to eq "restriction:MyJob:#{Time.now.to_i / (24*60*60)}"
      expect(MyJob.redis_key(:per_month)).to eq "restriction:MyJob:#{Date.today.strftime("%Y-%m")}"
      expect(MyJob.redis_key(:per_year)).to eq "restriction:MyJob:#{Date.today.year}"
      expect(MyJob.redis_key(:per_minute_and_foo, 'foo' => 'bar')).to eq "restriction:MyJob:bar:#{Time.now.to_i / 60}"
    end

    it "should accept customization" do
      expect(MyJob.redis_key(:per_1800)).to eq "restriction:MyJob:#{Time.now.to_i / 1800}"
      expect(MyJob.redis_key(:per_7200)).to eq "restriction:MyJob:#{Time.now.to_i / 7200}"
      expect(MyJob.redis_key(:per_1800_and_foo, 'foo' => 'bar')).to eq "restriction:MyJob:bar:#{Time.now.to_i / 1800}"
    end
  end

  context "seconds" do
    it "should get seconds with different period" do
      expect(MyJob.seconds(:per_minute)).to eq 60
      expect(MyJob.seconds(:per_hour)).to eq 60*60
      expect(MyJob.seconds(:per_day)).to eq 24*60*60
      expect(MyJob.seconds(:per_week)).to eq 7*24*60*60
      expect(MyJob.seconds(:per_month)).to eq 31*24*60*60
      expect(MyJob.seconds(:per_year)).to eq 366*24*60*60
      expect(MyJob.seconds(:per_minute_and_foo)).to eq 60
    end

    it "should accept customization" do
      expect(MyJob.seconds(:per_1800)).to eq 1800
      expect(MyJob.seconds(:per_7200)).to eq 7200
      expect(MyJob.seconds(:per_1800_and_foo)).to eq 1800
    end
  end

  context "restrictions" do
    it "gets correct restrictions from jobs" do
      expect(OneDayRestrictionJob.restrictions).to eq({:per_day => 100})
      expect(OneHourRestrictionJob.restrictions).to eq({:per_hour => 10})
      expect(MultipleRestrictionJob.restrictions).to eq({:per_hour => 10, :per_300 => 2})
      expect(MultiCallRestrictionJob.restrictions).to eq({:per_hour => 10, :per_300 => 2})
    end

    it "gets dynamic restrictions from jobs" do
      expect(DynamicRestrictionJob.restrictions('custom', :per_hour => 10)).to eq({:per_minute => 5, :per_hour => 10})
      expect(DynamicRestrictionJob.restrictions('custom', :per_minute => 1)).to eq({:per_minute => 1})
    end
  end

  context 'restriction_queue_name' do
    it 'concats restriction queue prefix with queue name' do
      expect(MyJob.restriction_queue_name).to eq("#{Resque::Plugins::Restriction::RESTRICTION_QUEUE_PREFIX}_awesome_queue_name")
    end
  end

  context "resque" do
    include PerformJob

    before(:example) do
      Resque.redis.flushall
    end

    it "should set execution number and increment it when one job first executed" do
      result = perform_job(OneHourRestrictionJob, "any args")
      expect(Resque.redis.get(OneHourRestrictionJob.redis_key(:per_hour))).to eq "1"
    end

    it "should use restriction_identifier to set exclusive execution counts" do
      result = perform_job(IdentifiedRestrictionJob, 1)
      result = perform_job(IdentifiedRestrictionJob, 1)
      result = perform_job(IdentifiedRestrictionJob, 2)

      expect(Resque.redis.get(IdentifiedRestrictionJob.redis_key(:per_hour, 1))).to eq "2"
      expect(Resque.redis.get(IdentifiedRestrictionJob.redis_key(:per_hour, 2))).to eq "1"
    end

    it "should use dynamic restrictions" do
      result = perform_job(DynamicRestrictionJob, 1, :per_hour => 5)
      result = perform_job(DynamicRestrictionJob, 1, :per_hour => 5)
      result = perform_job(DynamicRestrictionJob, 2, :per_hour => 10)

      expect(Resque.redis.get(DynamicRestrictionJob.redis_key(:per_hour, 1))).to eq "2"
      expect(Resque.redis.get(DynamicRestrictionJob.redis_key(:per_hour, 2))).to eq "1"

      expect(Resque.redis.get(DynamicRestrictionJob.redis_key(:per_minute, 1))).to eq "2"
      expect(Resque.redis.get(DynamicRestrictionJob.redis_key(:per_minute, 2))).to eq "1"
    end

    it "should increment execution number when one job executed" do
      Resque.redis.set(OneHourRestrictionJob.redis_key(:per_hour), 6)
      result = perform_job(OneHourRestrictionJob, "any args")

      expect(Resque.redis.get(OneHourRestrictionJob.redis_key(:per_hour))).to eq "7"
    end

    it "should increment execution number when concurrent job completes" do
      t = Thread.new do
        perform_job(ConcurrentRestrictionJob, "any args")
      end
      sleep 0.1
      concurrency_key = ConcurrentRestrictionJob.redis_key(:concurrent)
      expect(Resque.redis.zcard(concurrency_key)).to eq 1
      t.join
      expect(Resque.redis.zcard(concurrency_key)).to eq 0
    end

    it "should increment execution number when concurrent job fails" do
      expect(ConcurrentRestrictionJob).to receive(:perform).and_raise("bad")
      perform_job(ConcurrentRestrictionJob, "any args") rescue nil
      expect(Resque.redis.zcard(ConcurrentRestrictionJob.redis_key(:concurrent))).to eq 0
    end

    it "should put the job into restriction queue when execution count > limit" do
      Resque.redis.set(OneHourRestrictionJob.redis_key(:per_hour), 10)
      result = perform_job(OneHourRestrictionJob, "any args")
      # expect(result).to_not be(true)
      expect(Resque.redis.get(OneHourRestrictionJob.redis_key(:per_hour))).to eq "10"
      expect(Resque.redis.lrange("queue:restriction_normal", 0, -1)).to eq [Resque.encode(:class => "OneHourRestrictionJob", :args => ["any args"])]
    end

    describe "expiration of period keys" do
      class MyJob
        extend Resque::Plugins::Restriction

        def self.perform(*args)
        end
      end

      shared_examples_for "expiration" do
        before(:example) do
          MyJob.restrict period => 10
        end

        context "when the key is not set" do
          it "should mark period keys to expire" do
            perform_job(MyJob, "any args")
            expect(Resque.redis.ttl(MyJob.redis_key(period))).to eq MyJob.seconds(period)
          end
        end

        context "when the key is set" do
          before(:example) do
            Resque.redis.set(MyJob.redis_key(period), 5)
          end

          it "should not mark period keys to expire" do
            perform_job(MyJob, "any args")
            expect(Resque.redis.ttl(MyJob.redis_key(period))).to eq -1
          end
        end
      end

      describe "per second" do
        def period
          :per_second
        end

        it_should_behave_like "expiration"
      end

      describe "per minute" do
        def period
          :per_minute
        end

        it_should_behave_like "expiration"
      end

      describe "per hour" do
        def period
          :per_hour
        end

        it_should_behave_like "expiration"
      end

      describe "per day" do
        def period
          :per_day
        end

        it_should_behave_like "expiration"
      end

      describe "per week" do
        def period
          :per_week
        end

        it_should_behave_like "expiration"
      end

      describe "per month" do
        def period
          :per_month
        end

        it_should_behave_like "expiration"
      end

      describe "per year" do
        def period
          :per_year
        end

        it_should_behave_like "expiration"
      end

      describe "per custom period" do
        def period
          :per_359
        end

        it_should_behave_like "expiration"
      end
    end

    context "multiple restrict" do
      it "should restrict per_minute" do
        result = perform_job(MultipleRestrictionJob, "any args")
        expect(Resque.redis.get(MultipleRestrictionJob.redis_key(:per_hour))).to eq "1"
        expect(Resque.redis.get(MultipleRestrictionJob.redis_key(:per_300))).to eq "1"
        result = perform_job(MultipleRestrictionJob, "any args")
        result = perform_job(MultipleRestrictionJob, "any args")
        expect(Resque.redis.get(MultipleRestrictionJob.redis_key(:per_hour))).to eq "2"
        expect(Resque.redis.get(MultipleRestrictionJob.redis_key(:per_300))).to eq "2"
      end

      it "should restrict per_hour" do
        Resque.redis.set(MultipleRestrictionJob.redis_key(:per_hour), 9)
        Resque.redis.set(MultipleRestrictionJob.redis_key(:per_300), 0)
        result = perform_job(MultipleRestrictionJob, "any args")
        expect(Resque.redis.get(MultipleRestrictionJob.redis_key(:per_hour))).to eq "10"
        expect(Resque.redis.get(MultipleRestrictionJob.redis_key(:per_300))).to eq "1"
        result = perform_job(MultipleRestrictionJob, "any args")
        expect(Resque.redis.get(MultipleRestrictionJob.redis_key(:per_hour))).to eq "10"
        expect(Resque.redis.get(MultipleRestrictionJob.redis_key(:per_300))).to eq "1"
      end
    end

    context "repush" do
      it "should push restricted jobs onto restriction queue" do
        Resque.redis.set(OneHourRestrictionJob.redis_key(:per_hour), 10)
        expect(Resque).to receive(:push).once.with('restriction_normal', :class => 'OneHourRestrictionJob', :args => ['any args'])
        expect(OneHourRestrictionJob.repush_if_restricted('any args')).to be(true)
      end

      it "should not push unrestricted jobs onto restriction queue" do
        Resque.redis.set(OneHourRestrictionJob.redis_key(:per_hour), 9)
        expect(Resque).not_to receive(:push)
        expect(OneHourRestrictionJob.repush_if_restricted('any args')).to be(false)
      end
    end
  end
end
