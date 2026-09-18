# frozen_string_literal: true

module PubSubModelSync
  # Stands in for a google-cloud-pubsub 3.x client.
  #
  # Topics and subscriptions have to be created before they can be looked up,
  # exactly as they do in 3.x: +publisher+ and +subscriber+ raise NotFoundError
  # for a name nobody has created rather than answering nil.
  class MockGoogleService
    class MockStop
      def wait!
        true
      end
    end

    class MockListener
      def start
        true
      end

      def on_error(&_block)
        true
      end

      def stop
        @stop ||= MockStop.new
      end
      alias stop! stop
    end

    class MockSubscriber
      def listen(*_args, **_kwargs, &_block)
        @listen ||= MockListener.new
      end
    end

    # What google-cloud-pubsub yields to an async publish callback. Only the
    # success case is mocked: a caller that needs a failed publish stubs
    # #publish_async and yields its own result.
    class MockAsyncResult
      def succeeded?
        true
      end
    end

    class MockPublisher
      attr_reader :name

      def initialize(name = 'name')
        @name = name
      end

      def publish(*_args, **_kwargs)
        true
      end

      def publish_async(*_args, **_kwargs)
        yield(MockAsyncResult.new) if block_given?
      end

      def resume_publish(_ordering_key)
        true
      end

      def enable_message_ordering!
        true
      end
    end

    class MockTopicAdmin
      def initialize(service)
        @service = service
      end

      def create_topic(name:)
        @service.created_topics << name
        true
      end
    end

    class MockSubscriptionAdmin
      def initialize(service)
        @service = service
      end

      def create_subscription(name:, topic:, **_settings)
        @service.created_subscriptions << name
        topic
      end
    end

    attr_reader :created_topics, :created_subscriptions, :publishers

    # @param existing (Boolean): whether the topic and the subscription are
    #   already there. False makes the first lookup of each raise, which is what
    #   sends the service down its create-then-look-up-again path.
    def initialize(existing: true)
      @created_topics = []
      @created_subscriptions = []
      @publishers = {}
      return unless existing

      @created_topics << topic_path('ps_sync')
      @created_subscriptions << subscription_path('ps_sync')
    end

    def topic_path(name)
      "projects/test/topics/#{name}"
    end

    def subscription_path(name)
      "projects/test/subscriptions/#{name}"
    end

    def topic_admin
      @topic_admin ||= MockTopicAdmin.new(self)
    end

    def subscription_admin
      @subscription_admin ||= MockSubscriptionAdmin.new(self)
    end

    def publisher(topic_name)
      raise Google::Cloud::NotFoundError, 'topic not found' unless created_topics.include?(topic_path(topic_name))

      publishers[topic_name] ||= MockPublisher.new(topic_path(topic_name))
    end

    def subscriber(subs_name)
      unless created_subscriptions.include?(subscription_path(subs_name))
        raise Google::Cloud::NotFoundError, 'subscription not found'
      end

      @subscriber ||= MockSubscriber.new
    end
  end
end
