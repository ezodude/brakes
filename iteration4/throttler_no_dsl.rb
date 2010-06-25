class Throttler
  THROTTLE = true
  RESET= false
  
  # KNOWN_CONTEXTS = [:throttle, :reset]
  
  attr_reader :throttling_factor
  
  def initialize(throttling_sequence)
    @throttling_sequence = throttling_sequence
    @context_procs = []
    @throttling_factor = @throttling_sequence[0]
  end
  
  def known_context?(candidate)
    KNOWN_CONTEXTS.include?(candidate)
  end
  
  def available_contexts
    KNOWN_CONTEXTS
  end
  
  def throttle
    @context_procs << [block, THROTTLE]
  end
  
  def reset
    @context_procs << [block, RESET]
  end
  
  def evaluate(value)
    context_pair = @context_procs.detect{ |block, intent| block.call(value) }
    can_throttle = context_pair ? context_pair[1] : nil
    can_throttle ? proceed_to_next_throttle_factor : reset_throttle_factor
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

# Registering evaluations that will change the context
throttler.throttle {|value| value == :foo }
# throttler.register(:throttle) {|value| value == :foo }
# throttler.register(:throttle) {|value| value == :foo_bar }
# throttler.register(:reset) {|value| value == :bar}

values = [:foo, :bar, :foo_bar]
while true
  throttler.run do |throttler|
    value = values[rand(values.size)]
    puts "value: [#{value}]"
    throttler.evaluate value
  end
  puts "throttling_factor: [#{throttler.throttling_factor}]"
end
