module Resque
  module Plugins
    module Restriction
      # A redis-based concurrency limiter
      # Allows a max number of concurrent jobs to run for a given key
      # Assumes all workers clocks are synchronized (allows for 60s of clock skew)
      # The heartbeat approach protects against catastrophic failure
      # e.g., if a process is killed, the slot reservation will go stale,
      # get ignored, and be cleaned up by other jobs
      class ConcurrencyLimiter
        JOB_ID_KEY           = 'restriction:concurrency_job_id'.freeze
        CONCURRENT_HEARTBEAT = 15
        MAX_CLOCK_SKEW       = 60
        STALE_TTL            = MAX_CLOCK_SKEW + CONCURRENT_HEARTBEAT

        # @param [Redis] redis
        def initialize(redis)
          # @type [Redis]
          @redis = redis
        end

        # Try to reserve a concurrency slot for the given key and max concurrency
        # @returns true if a slot is acquired, false otherwise
        def try_start(key, concurrency)
          @job_id = @redis.incr(JOB_ID_KEY)
          now     = Time.now.to_i
          result  = @redis.multi do
            @redis.zadd(key, now, @job_id)
            @redis.zcount(key, (now - STALE_TTL).to_s, (now + MAX_CLOCK_SKEW).to_s)
          end

          if result[1].to_i <= concurrency
            start_heartbeat(key)
            true
          else
            @redis.zrem(key, @job_id)
            false
          end
        end

        # Check if there is capacity for another job for the key given the max concurrency
        def can_start?(key, concurrency)
          now = Time.now.to_i
          @redis.zcount(key, now - STALE_TTL, now + MAX_CLOCK_SKEW).to_i < concurrency
        end

        # Give up the reserved slot
        def finish(key)
          stop_heartbeat
          return if @job_id.nil?
          @redis.zrem(key, @job_id)
          @job_id = nil
        end

        private

        def perform_maintenance(key)
          # Remove stale members (e.g., from a process that unwillingly exits)
          @redis.zremrangebyscore(key, '0', (Time.now.to_i - STALE_TTL).to_s)
        end

        # Continually update the score (timestamp) for this job
        # Keeps the job slot until the job is finished
        def start_heartbeat(key)
          stop_heartbeat
          @thread = Thread.new do
            perform_maintenance(key) if rand(100).zero?
            loop do
              sleep(CONCURRENT_HEARTBEAT)
              @redis.pipelined do
                @redis.zadd(key, Time.now.to_i, @job_id, xx: true)
              end
            end
          end
        end

        def stop_heartbeat
          @thread.kill.join if @thread
          @thread = nil
        end
      end
    end
  end
end
