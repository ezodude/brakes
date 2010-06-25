
# 
# This where the idea for a client throttling library/DSL came from.
# Here throttling functionality is interweaved with domain logic adding yet another layer of 
# complexity to already complex code.
#
# HINT: If you're brave, follow where the THROTTLE_SEQUENCE constant is used to get an idea of how the throttling works.
#

require 'smqueue'

module OfflineServices
  class WritebackScript < Base
    
    QUEUE_CONSUMER = "writeback"
    PROCESSED_OBJECT_TYPE = "remote_service_object"

    TIMEOUT = 10.seconds
    THROTTLE_SEQUENCE = [0, 3, 5, 10, 20]

    attr_reader :current_throttle_factor
    # TIMEOUT is used to control:
    #
    # 1) How long we will wait for a conection to the remote service to open
    # 2) How long after that connection is open we'll wait to be sent the first 
    #    byte of a response.
    #
    # Note that this means for each request we can wait up to 2*TIMEOUT before a 
    # TimeoutError is raised.
    #
    
    def initialize
      @current_throttle_factor = THROTTLE_SEQUENCE[0]
    end
    
    def execute
      logger.info "#{File.basename($0)} starting"

      mq = HashWithIndifferentAccess.new(YAML::load(File.read(File.join(RAILS_ROOT, 'config', 'message_queue.yml'))))

      logger.info "Incoming queue configuration: #{mq[:writeback].inspect}"
      logger.info "Unlock queue configuration: #{mq[:writeback_unlock].inspect}"
      
      xml_queue_name = mq[:writeback][:name]
      xml = SMQueue.new(mq[:writeback].merge(:client_id => client_id))
      
      unlocker = SMQueue.new(mq[:writeback_unlock].merge(:client_id => client_id + ".unlocker"))

      xml.get do |message|
        process(message, xml_queue_name, unlocker)
      end
    end
    
    def process(message, xml_queue_name, unlocker_queue)
      RemoteService::Base.verify_active_connections!

      logger.debug "Start processing message #{message.inspect}"
      update = YAML::parse(message.body).transform
      logger.debug "Update message: #{update.inspect}"
      
      if update.key?(:xml) && !update[:xml].blank?
        begin
          sleep(@current_throttle_factor)
          
          logger.info "Start processing XML writeback for message containing id: [#{update[:id]}] and lock id: [#{update[:lock_id]}]."
          
          Net::HTTP.start(REMOTE_SERVICE_URI, REMOTE_SERVICE_PORT.to_s) do |http|
            http.open_timeout = TIMEOUT
            http.read_timeout = TIMEOUT
            
            logger.debug("Posting to Remote Service #{REMOTE_SERVICE_URI}:#{REMOTE_SERVICE_PORT}")
            request = Net::HTTP::Post.new('/import/xml')
            request.set_content_type('application/xml')
            request.basic_auth(REMOTE_SERVICE_PROX_AUTH_USER, REMOTE_SERVICE_PROX_AUTH_PWD)
            request.add_field("User-Agent", "Tool (#{APPLICATION_RELEASE} v#{APPLICATION_BUILD}) / RemoteService Writer")
            
            user = if update[:user_id]
              User.find_by_id(update[:user_id])
            end

            request.add_field("X-User", user.blank? ? "CLIENT" : user.login)
            response = http.request(request, update[:xml])
            
            logger.debug("Request returned from Remote Service")
            case response
              when Net::HTTPSuccess
                @current_throttle_factor = 0
                
                if update.key?(:lock_id)
                  logger.info "Requesting removal of lock #{update[:lock_id]}"
                  unlocker_queue.put({ :lock_id => update[:lock_id] }.to_yaml)
                end
            
                doc = Hpricot(response.body)
                import_id = (doc / "remote_service/import").first['iid']
                duration = (doc / "remote_service/import").first['duration']

                logger.info "Wrote XML to RemoteService for object id: [#{update[:id]}] in import id: [#{import_id}] in (#{duration}s)"
                
              when Net::HTTPClientError
                @current_throttle_factor = 0
                
                logger.warn "Creating a Failed Event after attempting to write XML to RemoteService for object id: [#{update[:id]}] and lock id: [#{update[:lock_id]}]."
                create_failed_event(update[:lock_id], xml_queue_name, update[:id], message.body, 
                  "Response code received: [#{response.code}], message: [#{response.message}].")
                  
              when Net::HTTPServerError
                throttle_index = THROTTLE_SEQUENCE.index(@current_throttle_factor)
                @current_throttle_factor = THROTTLE_SEQUENCE[(throttle_index + 1) % THROTTLE_SEQUENCE.size]

                if update[:attempt].to_i < 4 
                  logger.info "Failed to write XML to RemoteService for object id: [#{update[:id]}] and lock id: [#{update[:lock_id]}] on attempt [#{(update[:attempt] + 1).to_s}] of 5. Retrying."
                  update[:attempt] = update[:attempt].to_i + 1
                  RemoteService::Base.xml_writer.put update.to_yaml
                else
                  logger.warn "Creating a Failed Event after attempting to write XML to RemoteService for object id: [#{update[:id]}] and lock id: [#{update[:lock_id]}] after 5 attempts."
                  create_failed_event(update[:lock_id], xml_queue_name, update[:id], message.body, 
                    "Response code received: [#{response.code}], message: [#{response.message}].")
                end
                
              else
                @current_throttle_factor = 0
                
                logger.warn "Creating a Failed Event after attempting to write XML to RemoteService for object id: [#{update[:id]}] and lock id: [#{update[:lock_id]}]."
                create_failed_event(update[:lock_id], xml_queue_name, update[:id], message.body, 
                  "Response code received: [#{response.code}], message: [#{response.message}].")
            end
          end
        rescue Errno::ENETUNREACH, TimeoutError => e
          logger.warn "Connection to RemoteService timed out: #{e.inspect}. Requeuing writeback request."
          RemoteService::Base.xml_writer.put(update.to_yaml)
        end
      else
        logger.warn "No XML in message. Discarding."
        unlocker_queue.put({ :lock_id => update[:lock_id] }.to_yaml) if update.key?(:lock_id)
      end
      logger.debug "Finished processing message #{message.inspect}"
    end
    
  private

    def create_failed_event(editorial_lock_id, source, editorial_object_id, message_body, error)
      attrs = {
                :edit_lock_id => editorial_lock_id,
                :source => source,
                :consumer => QUEUE_CONSUMER, 
                :editorial_object_id => editorial_object_id,
                :editorial_object_type => PROCESSED_OBJECT_TYPE, 
                :action => QUEUE_CONSUMER,
                :message => message_body,
                :error => error
              }
      FailedEvent.create(attrs)
    end
  end
end
