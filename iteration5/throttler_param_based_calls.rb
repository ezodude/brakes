class Throttler
  KNOWN_CONTEXTS = [:throttle, :reset]
  
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
  
  def register(context, &block)
    ensure_context_is_known(context)
    @context_procs << [block, context]
  end
  
  def evaluate(value)
    context_proc = @context_procs.detect{ |block, intent| block.call(value) }
    context = context_proc ? context_proc[1] : nil
    context == :throttle ? proceed_to_next_throttle_factor : reset_throttle_factor
  end
  
  def run
    sleep(@throttling_factor)
    yield self
  end
  
private
  
  def ensure_context_is_known(candidate)
    raise "Unkown context [#{candidate}]" unless KNOWN_CONTEXTS.include?(candidate)
  end
  
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
throttler.register(:throttle) {|value| value == :foo }
throttler.register(:throttle) {|value| value == :foo_bar }
throttler.register(:reset) {|value| value == :bar}

values = [:foo, :bar, :foo_bar]
while true
  throttler.run do |throttler|
    value = values[rand(values.size)]
    puts "value: [#{value}]"
    throttler.evaluate value
  end
  puts "throttling_factor: [#{throttler.throttling_factor}]"
end
