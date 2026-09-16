# frozen_string_literal: true

begin
  require 'google/cloud/pubsub'
rescue LoadError # rubocop:disable Lint/SuppressedException
end

module PubSubModelSync
  # google-cloud-pubsub 3.0 reorganised the client: Project#topic and
  # Topic#subscription are gone, replaced by Project#publisher and
  # Project#subscriber, both of which look the resource up and raise
  # NotFoundError rather than answering nil. Creating either one now goes
  # through the admin clients.
  #
  # The accessors keep their names and their roles: +topic+ is what messages are
  # published to, +subscription+ is what is listened on, and +subscriber+ is the
  # listener that #stop stops.
  class ServiceGoogle < ServiceBase
    attr_accessor :service, :topic, :subscription, :config, :subscriber

    def initialize
      super
      @config = PubSubModelSync::Config
      @service = Google::Cloud::Pubsub.new(project_id: config.project,
                                           credentials: config.credentials)
      @topic = publisher_for_topic
    end

    def listen_messages
      @subscription = subscribe_to_topic
      @subscriber = subscription.listen(&method(:process_message))
      log('Listener starting...')
      subscriber.start
      log('Listener started')
      sleep
      subscriber.stop.wait!
      log('Listener stopped')
    end

    def publish(data, attributes)
      log("Publishing message: #{[attributes, data]}")
      payload = { data: data, attributes: attributes }.to_json
      topic.publish(payload, { SERVICE_KEY => true })
    rescue => e
      info = [attributes, data, e.message, e.backtrace]
      log("Error publishing: #{info}", :error)
    end

    def stop
      log('Listener stopping...')
      subscriber.stop!
    end

    private

    def publisher_for_topic
      service.publisher(config.topic_name)
    rescue Google::Cloud::NotFoundError
      service.topic_admin
             .create_topic(name: service.topic_path(config.topic_name))
      service.publisher(config.topic_name)
    end

    def subscribe_to_topic
      service.subscriber(config.subscription_name)
    rescue Google::Cloud::NotFoundError
      create_subscription
      service.subscriber(config.subscription_name)
    end

    def create_subscription
      service.subscription_admin.create_subscription(
        name: service.subscription_path(config.subscription_name),
        topic: service.topic_path(config.topic_name)
      )
    end

    def process_message(received_message)
      message = received_message.message
      return unless message.attributes[SERVICE_KEY]

      perform_message(message.data)
    rescue => e
      log("Error processing message: #{[received_message, e.message]}", :error)
    ensure
      received_message.acknowledge!
    end

    def log(msg, kind = :info)
      config.log("Google Service ==> #{msg}", kind)
    end
  end
end
