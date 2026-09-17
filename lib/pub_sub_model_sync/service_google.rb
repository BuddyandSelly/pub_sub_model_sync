# frozen_string_literal: true

begin
  require 'google/cloud/pubsub'
rescue LoadError # rubocop:disable Lint/SuppressedException
end

module PubSubModelSync
  # Google Pub/Sub transport, written against the google-cloud-pubsub 3.x API.
  #
  # 3.0 reorganised the client and removed what 1.x/2.x offered:
  #
  #   Google::Cloud::PubSub.new(project:)  -> .new(project_id:)
  #   client.topic / create_topic          -> client.publisher / client.topic_admin
  #   topic.subscription / topic.subscribe -> client.subscriber / client.subscription_admin
  #   Topic#publish / #publish_async       -> Publisher#publish / #publish_async
  #
  # Only the transport differs from what this gem published as 1.9.3: the wire
  # format still comes from ServiceBase#encode_payload and #process_message, so
  # payloads stay compatible with any service still on the older client.
  class ServiceGoogle < ServiceBase
    LISTEN_SETTINGS = { message_ordering: true }.freeze
    PUBLISH_SETTINGS = {}.freeze
    SUBSCRIPTION_SETTINGS = { enable_message_ordering: true }.freeze

    # @!attribute service (Google::Cloud::PubSub::Project)
    # @!attribute publishers (Hash): { topic_name => Publisher } used to listen & publish
    # @!attribute publish_publishers (Hash): { topic_name => Publisher } publish only
    attr_accessor :service, :publishers, :publish_publishers, :listeners

    def initialize
      super
      @service = Google::Cloud::PubSub.new(project_id: config.project,
                                           credentials: config.credentials)
      @publishers = {}
      @publish_publishers = {}
      Array(config.topic_name || 'model_sync').each { |name| init_publisher(name) }
    end

    def listen_messages
      log('Listener starting...')
      @listeners = subscribe_to_topics
      log('Listener started')
      sleep
      listeners.each { |listener| listener.stop.wait! }
      log('Listener stopped')
    end

    # @param payload (PubSubModelSync::Payload)
    def publish(payload)
      p_topic_names = Array(payload.headers[:topic_name] || config.default_topic_name)
      p_topic_names.map { |name| find_publisher(name) }.each do |publisher|
        publish_to_topic(publisher, payload)
      end
    end

    def stop
      log('Listener stopping...')
      (listeners || []).each(&:stop!)
    end

    private

    def find_publisher(topic_name)
      topic_name = topic_name.to_s
      return publishers.values.first if topic_name.blank?

      publishers[topic_name] || publish_publishers[topic_name] ||
        init_publisher(topic_name, only_publish: true)
    end

    def publish_to_topic(publisher, payload)
      retries ||= 0
      publish_message(publisher, payload)
    rescue Google::Cloud::PubSub::OrderingKeyError => e
      raise if (retries += 1) > 1

      log("Resuming ordering_key and retrying OrderingKeyError for #{payload.uuid}: #{e.message}")
      publisher.resume_publish(payload.ordering_key)
      retry
    end

    def publish_message(publisher, payload)
      data, attributes = message_params(payload)
      if config.sync_mode
        publisher.publish(data, attributes, ordering_key: payload.ordering_key)
      else
        publisher.publish_async(data, attributes, ordering_key: payload.ordering_key) do |result|
          check_async_result(result, payload)
        end
      end
    end

    def check_async_result(result, payload)
      log "Published message: #{payload.uuid} (via async)" if result.succeeded? && config.debug
      return if result.succeeded?

      log("Error publishing: #{[payload, result.error]} (via async)", :error)
      config.on_error_publish.call(StandardError.new(result.error), { payload: payload })
    end

    # Loads the topic, creating it when missing, and returns a publisher for it.
    # In 3.x #publisher raises NotFoundError instead of returning nil, and topic
    # creation moved to the TopicAdmin client.
    #
    # @param only_publish (Boolean): when false the topic is also listened to
    # @return (Google::Cloud::PubSub::Publisher)
    def init_publisher(topic_name, only_publish: false)
      topic_name = topic_name.to_s
      publisher = find_or_create_publisher(topic_name)
      publisher.enable_message_ordering!
      publish_publishers[topic_name] = publisher if only_publish
      publishers[topic_name] = publisher unless only_publish
      publisher
    end

    def find_or_create_publisher(topic_name)
      service.publisher(topic_name)
    rescue Google::Cloud::NotFoundError
      log("Creating topic: #{topic_name}")
      service.topic_admin.create_topic(name: service.topic_path(topic_name))
      service.publisher(topic_name)
    end

    # @param payload (PubSubModelSync::Payload)
    # @return [Array<String, Hash>]
    def message_params(payload)
      [
        encode_payload(payload),
        { SERVICE_KEY => true }.merge(PUBLISH_SETTINGS)
      ]
    end

    # @return [Array<Google::Cloud::PubSub::MessageListener>]
    def subscribe_to_topics
      publishers.map do |key, publisher|
        subs_name = "#{config.subscription_key}_#{key}"
        subscriber = find_or_create_subscriber(subs_name, publisher.name)
        listener = subscriber.listen(**LISTEN_SETTINGS, &method(:process_message))
        listener.on_error { |error| log("Subscriber error: #{error.class} #{error.message}", :error) }
        listener.start
        log("Subscribed to topic: #{publisher.name} as: #{subs_name}")
        listener
      end
    end

    def find_or_create_subscriber(subs_name, topic_path)
      service.subscriber(subs_name)
    rescue Google::Cloud::NotFoundError
      log("Creating subscription: #{subs_name}")
      service.subscription_admin.create_subscription(
        name: service.subscription_path(subs_name), topic: topic_path, **SUBSCRIPTION_SETTINGS
      )
      service.subscriber(subs_name)
    end

    def process_message(received_message)
      message = received_message.message
      if message.attributes[SERVICE_KEY]
        super(message.data)
      elsif config.debug
        log("Unknown message (#{SERVICE_KEY}): #{[message, message.attributes]}")
      end
      received_message.acknowledge!
    end
  end
end
