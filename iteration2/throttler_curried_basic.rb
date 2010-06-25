# Introduces some interesting Connascence of name
# 'throttle' method => ':throttle' intent
# 'reset' method => ':reset' intent
#  We're only doing this to provide what I think might be a more expressive interface

class Object
  def current_method
    p [:caller, caller[0]]
    caller[0] =~ /\d:in `([^']+)'/
    $1
  end
end

class Throttler
  class ThrottlerProxy
    def initialize(throttler, intent)
      @throttler, @intent = throttler, intent
    end
    
    def register(&block)
      @throttler.register(@intent, &block)
    end
  end
  
  attr_reader :throttling_factor
  
  def initialize(throttling_sequence)
    @throttling_sequence = throttling_sequence
    @context_procs = []
    @throttling_factor = @throttling_sequence[0]
  end
  
  def register(intent, &block)
    raise "Unkown intent [#{intent}]" unless [:throttle, :reset].include?(intent)
    @context_procs << [block, intent]
  end
  
  def handler(intent, &block)
    block_given? ? yield(ThrottlerProxy.new(self, intent)) : ThrottlerProxy.new(self, intent)
  end
  
  def throttle(&block)
    handler(:throttle, &block)
  end
  
  def reset(&block)
    handler(:reset, &block)
  end
  
  def evaluate(value)
    context_proc = @context_procs.detect{ |block, intent| block.call(value) }
    intent = context_proc ? context_proc[1] : nil
    # puts "INTENT: [#{intent.inspect}]"
    intent == :throttle ? proceed_to_next_throttle_factor : reset_throttle_factor
  end
  
  def run
    sleep(@throttling_factor)
    yield self
  end
  
private
  
  def reset_throttle_factor
    @throttling_factor = @throttling_sequence[0]
  end
  
  def proceed_to_next_throttle_factor
    throttling_index = @throttling_sequence.index(@throttling_factor)
    @throttling_factor = @throttling_sequence[(throttling_index + 1) % @throttling_sequence.size]
  end
end

throttler = Throttler.new([0, 10, 20])

# Couldn't use 'throttler' as block variable because of Ruby 1.8 block variable shadowing.

# throttler.throttle.register {|value| value == :foo}
# throttler.reset.register {|value| value == :bar}

# Registering evaluations that will change the context
throttler.throttle do |throttler_proxy|
 throttler_proxy.register {|value| value == :foo}
end
throttler.reset do |throttler_proxy|
  throttler_proxy.register {|value| value == :bar}
end

values = [:foo, :bar]
while true
  throttler.run do |throttler|
    value = values[rand(values.size)]
    puts "value: [#{value}]"
    throttler.evaluate value
  end
  puts "throttling_factor: [#{throttler.throttling_factor}]"
end
