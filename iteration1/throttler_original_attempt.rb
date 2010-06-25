class Throttler 
  attr_reader :throttling_factor
  
  def initialize(throttling_sequence)
    @throttling_sequence = throttling_sequence
    @throttling_factor = throttling_sequence[0]
    @registered_actions = {}
    @setup_status = {}
  end
  
  def reset
    @setup_status = {:register_status => :reset, :context => :direct}
    
    return self unless block_given?
    @setup_status.merge!({:context => :block})
    yield self 
    @setup_status[:register_status] = nil 
  end
  
  def increment
    @setup_status = {:register_status => :increment, :context => :direct}
    
    return self unless block_given?
    @setup_status.merge!({:context => :block})
    yield self 
    @setup_status[:register_status] = nil 
  end
  
  def register(&block)
    return if @setup_status[:register_status].nil?
    
    # FAIL: This is really wrong and will not work when you have multiple conditions to register for one event!
    @registered_actions[@setup_status[:register_status]] = block 
    @setup_status[:register_status] = nil if @setup_status[:context] == :direct
  end
  
  def evaluate(candidate)
    @registered_actions.each do |intent, evaluation_proc|
      if evaluation_proc.call(candidate)
        if intent == :increment
          throttling_index = @throttling_sequence.index(@throttling_factor)
          @throttling_factor = @throttling_sequence[(throttling_index + 1) % @throttling_sequence.size]
        else
          @throttling_factor = @throttling_sequence[0]
        end
        return
      end
    end
  end
  
  def run
    sleep(@throttling_factor)
    yield self
  end
end

throttler = Throttler.new([0, 1, 3, 5, 10])

# Registering evaluations that will change the context

throttler.increment do |throttler|
  throttler.register {|candidate| candidate == :foo}
end

# throttler.increment.register {|response| response.kind_of?(Net::HTTPServerError) }
throttler.reset.register {|candidate| candidate == :bar}

candidates = [:foo, :bar]
while true
  throttler.run do |throttler|
    candidate = candidates[rand(candidates.size)]
    puts "candidate: [#{candidate}]"
    throttler.evaluate candidate
  end
  puts "throttling_factor: [#{throttler.throttling_factor}]"
end

##############################################

# SUGGESTIONS SUGGESTIONS SUGGESTIONS SUGGESTIONS SUGGESTIONS SUGGESTIONS 

# PARAMS TO MAIN CONTEXT
# 
# throttler.register(:increment) { |res| ... }
# 
# @procs = [
#   [&block1, :increment],
#   [&block2, :reset],
#   ]
# 
# condition = @procs.first{|block, condition| block.call(value) ? condition : nil}

##############################################

# CURRIED OBJECTS TO MAINTAIN CONTEXT

# class ThrottlerProxy
#   def initialize(throttler, kind)
#     @throttler, @kind = throttler, kind
#   end
#   def register(&block)
#     @throttler.register(kind, &block)
#   end
# end
# 
# class Throttler
#   def register(kind, &block)
#     raise Exception unless [:increment, :reset].include?(kind)
#     @procs << [block, kind]
#   end
# 
#   def handler(kind, &block)
#     if block_given?
#       yield(ThrottlerProxy.new(self, kind))
#     else  
#       ThrottlerProxy.new(self, kind)
#     end
#   end
#   
#   def increment(&block)
#     handler(:increment, &block)
#   end
#   
#   def reset(&block)
#     handler(:reset, &block)
#   end
# end