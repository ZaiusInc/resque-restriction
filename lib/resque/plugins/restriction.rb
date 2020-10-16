module Resque
  module Plugins
    module Restriction
      SECONDS = {
        :per_second => 1,
        :per_minute => 60,
        :per_hour => 60*60,
        :per_day => 24*60*60,
        :per_week => 7*24*60*60,
        :per_month => 31*24*60*60,
        :per_year => 366*24*60*60
      }
      RESTRICTION_QUEUE_PREFIX = 'restriction'

      class IsRestrictedError < StandardError; end

      def base_restrictions
        @base_restrictions ||= {}
      end

      def restrict(options={})
        base_restrictions.merge!(options)
      end

      # Override for dynamic restrictions based on the job arguments
      # Note: to use dynamic restrictions, you should also implement dynamic identifiers
      # E.g., you should use the same unique restriction_identifier per each unique
      # set of restrictions if it matters
      # @param [Array] _args the job args
      def restrictions(*_args)
        base_restrictions
      end

      # Override for dynamic identifiers (restriction grouping) based on the job arguments
      # @param [Array] _args the job args
      def restriction_identifier(*_args)
        self.to_s
      end

      def concurrency_limiter
        @concurrency_limiter ||= ConcurrencyLimiter.new(Resque.redis)
      end

      def before_perform_restriction(*args)
        return if Resque.inline?

        keys_incremented = []
        concurrency_key = nil
        restrictions(*args).each do |period, number|
          key = redis_key(period, *args)

          # check if we would exceed the concurrency limit
          if period == :concurrent
            raise IsRestrictedError unless concurrency_limiter.try_start(key, number)
            concurrency_key = key
            next
          end

          # first try to set period key to be the total allowed for the period
          # if we get false back, the key wasn't set, so we know we are
          # already tracking the count for that period'
          period_active = ! Resque.redis.setnx(key, 1)
          # If we are already tracking that period, then increment by one and
          # see if we are allowed to run, pushing to restriction queue to run
          # later if not.  Note that the value stored is the number of jobs running,
          # thus we need to decrement if this job would exceed the limit
          if period_active
            value = Resque.redis.incrby(key, 1).to_i
            keys_incremented << [key, period]
            raise IsRestrictedError if value > number
          else
            # This is the first time we set the key, so we mark it to expire
            mark_restriction_key_to_expire_for(key, period)
          end
        end
      rescue IsRestrictedError
        # ensure we don't hold a concurrency slot
        concurrency_limiter.finish(concurrency_key) if concurrency_key

        # decrement the keys we incremented since we're not going to perform the job
        # so we accurately track capacity
        Resque.redis.pipelined do
          keys_incremented.each do |(k, period)|
            Resque.redis.incrby(k, -1)
            # There is an edge case where the key could have expired since we incremented it.
            # By setting the TTL again, we ensure we won't leave any keys behind
            mark_restriction_key_to_expire_for(k, period)
          end
        end

        Resque.push(restriction_queue_name, class: to_s, args: args)
        raise Resque::Job::DontPerform
      end

      def after_perform_restriction(*args)
        if restrictions(*args)[:concurrent]
          key = redis_key(:concurrent, *args)
          concurrency_limiter.finish(key)
        end
      end

      def on_failure_restriction(ex, *args)
        after_perform_restriction(*args)
      end

      def redis_key(period, *args)
        period_key, custom_key = period.to_s.split('_and_')
        period_str = case period_key.to_sym
                     when :concurrent then "*"
                     when :per_second, :per_minute, :per_hour, :per_day, :per_week then (Time.now.to_i / SECONDS[period_key.to_sym]).to_s
                     when :per_month then Date.today.strftime("%Y-%m")
                     when :per_year then Date.today.year.to_s
                     else period_key =~ /^per_(\d+)$/ and (Time.now.to_i / $1.to_i).to_s end
        custom_value = (custom_key && args.first && args.first.is_a?(Hash)) ? args.first[custom_key] : nil
        [RESTRICTION_QUEUE_PREFIX, self.restriction_identifier(*args), custom_value, period_str].compact.join(":")
      end

      def restriction_queue_name
        queue_name = Resque.queue_from_class(self)
        "#{RESTRICTION_QUEUE_PREFIX}_#{queue_name}"
      end

      def seconds(period)
        period_key, _ = period.to_s.split('_and_')
        if SECONDS.keys.include?(period_key.to_sym)
          SECONDS[period_key.to_sym]
        else
          period_key =~ /^per_(\d+)$/ and $1.to_i
        end
      end

      # if the job is already restricted, push to restriction queue.
      # Otherwise Resque will attempt to run the job, but restrictions
      # will be verified before it starts in `before_perform_restriction`
      def repush_if_restricted(*args)
        restrictions(*args).each do |period, number|
          key = redis_key(period, *args)
          if period == :concurrent
            raise IsRestrictedError unless concurrency_limiter.can_start?(key, number)
          else
            value = Resque.redis.get(key)
            raise IsRestrictedError if value && value != "" && value.to_i >= number
          end
        end
        false
      rescue IsRestrictedError
        # job is restricted, push to restriction queue
        Resque.push(restriction_queue_name, class: to_s, args: args)
        true
      end

      def mark_restriction_key_to_expire_for(key, period)
        Resque.redis.expire(key, seconds(period)) unless period == :concurrent
      end
    end
  end
end
