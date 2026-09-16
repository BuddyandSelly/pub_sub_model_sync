# frozen_string_literal: true

module PubSubModelSync
  # Mirrors the shape of google-cloud-pubsub 3.x: a project answers publishers
  # and subscribers by name, and the admin clients create what is missing.
  class MockGoogleService
    class MockStop
      def wait!
        true
      end
    end

    # What Subscriber#listen answers, and what ServiceGoogle#stop stops.
    class MockListener
      def start
        true
      end

      def stop
        @stop ||= MockStop.new
      end
      alias stop! stop
    end

    class MockSubscriber
      def listen(*_args)
        @listen ||= MockListener.new
      end
    end

    class MockPublisher
      def publish(*_args)
        true
      end
    end

    class MockTopicAdmin
      def create_topic(*_args)
        true
      end
    end

    class MockSubscriptionAdmin
      def create_subscription(*_args)
        true
      end
    end

    def publisher(*_args)
      @publisher ||= MockPublisher.new
    end

    def subscriber(*_args)
      @subscriber ||= MockSubscriber.new
    end

    def topic_admin
      @topic_admin ||= MockTopicAdmin.new
    end

    def subscription_admin
      @subscription_admin ||= MockSubscriptionAdmin.new
    end

    def topic_path(topic_name, *_args)
      "projects/mock-project/topics/#{topic_name}"
    end

    def subscription_path(subscription_name, *_args)
      "projects/mock-project/subscriptions/#{subscription_name}"
    end
  end
end
