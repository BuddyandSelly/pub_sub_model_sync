# frozen_string_literal: true

# The gem ships mock services so applications can test their syncs without a
# running pub/sub service. They only have to answer what the real services call.
RSpec.describe 'the mock services' do
  describe PubSubModelSync::MockGoogleService do
    let(:service) { described_class.new }

    it 'answers with the same publisher and subscriber' do
      expect(service.publisher('ps_sync')).to be(service.publisher('ps_sync'))
      expect(service.subscriber('ps_sync')).to be(service.subscriber('ps_sync'))
    end

    it 'answers a publisher per topic' do
      service.topic_admin.create_topic(name: service.topic_path('other'))

      expect(service.publisher('other')).not_to be(service.publisher('ps_sync'))
    end

    describe 'when the topic or the subscription was never created' do
      let(:service) { described_class.new(existing: false) }

      it 'raises as the real client does' do
        error = Google::Cloud::NotFoundError
        expect { service.publisher('ps_sync') }.to raise_error(error)
        expect { service.subscriber('ps_sync') }.to raise_error(error)
      end
    end

    it 'answers the admin interface' do
      sub_admin = service.subscription_admin

      expect(service.topic_admin).to be(service.topic_admin)
      expect(sub_admin).to be(service.subscription_admin)
      expect(service.topic_admin.create_topic(name: 'topic')).to be true
      expect(sub_admin.create_subscription(name: 'sub', topic: 'topic'))
        .to eq('topic')
    end

    it 'answers the resource paths' do
      expect(service.topic_path('name')).to eq('projects/test/topics/name')
      expect(service.subscription_path('name'))
        .to eq('projects/test/subscriptions/name')
    end

    it 'answers the listener interface' do
      subscriber = service.subscriber('ps_sync')
      listener = subscriber.listen

      expect(subscriber.listen).to be(listener)
      expect(listener.start).to be true
      expect(listener.on_error { nil }).to be true
      expect(listener.stop.wait!).to be true
      expect(listener.stop!).to be(listener.stop)
    end

    describe 'when publishing' do
      let(:publisher) { service.publisher('ps_sync') }

      it 'answers the publisher interface' do
        expect(publisher.name).to eq(service.topic_path('ps_sync'))
        expect(publisher.publish('payload', {})).to be true
        expect(publisher.resume_publish('key')).to be true
        expect(publisher.enable_message_ordering!).to be true
      end

      it 'calls back with a succeeded result when publishing async' do
        results = []

        publisher.publish_async('payload', {}) { |result| results << result }

        expect(results.map(&:succeeded?)).to eq([true])
      end

      it 'publishes async without a callback' do
        expect(publisher.publish_async('payload', {})).to be_nil
      end
    end
  end

  describe PubSubModelSync::MockRabbitService do
    let(:service) { described_class.new }
    let(:channel) { service.create_channel }

    it 'answers with the same channel' do
      expect(channel).to be(service.channel)
    end

    it 'answers the queue interface' do
      queue = channel.fanout('queue_name')

      expect(channel.queue).to be(queue)
      expect(queue.name).to eq('name')
      expect(queue.bind(channel.topic, routing_key: queue.name)).to be true
      expect(queue.subscribe).to be true
      expect(queue.publish('payload', {})).to be true
      expect(queue.channel).to be_a(described_class::MockChannel)
    end

    it 'answers publishing' do
      expect(channel.topic).to be(channel.topic)
      expect(channel.topic.publish('payload', {})).to be true
    end

    it 'answers acknowledging a message' do
      expect(channel.ack('delivery_tag')).to be true
    end

    it 'answers connecting and closing' do
      expect(service.start).to be true
      expect(channel.close).to be true
      expect(service.close).to be true
    end
  end

  describe PubSubModelSync::MockKafkaService do
    let(:service) { described_class.new }

    it 'answers the producer interface' do
      producer = service.async_producer

      expect(producer.produce('payload', {})).to be true
      expect(producer.deliver_messages).to be true
      expect(producer.shutdown).to be true
    end

    it 'answers the consumer interface' do
      consumer = service.consumer

      expect(consumer.subscribe('topic')).to be true
      expect(consumer.each_message).to be true
      expect(consumer.mark_message_as_processed('message')).to be true
      expect(consumer.stop).to be true
    end

    it 'answers the topic interface' do
      expect(service.topics).to eq([])
      expect(service.create_topic('topic')).to be true
    end

    it 'answers closing' do
      expect(service.close).to be true
    end
  end
end
