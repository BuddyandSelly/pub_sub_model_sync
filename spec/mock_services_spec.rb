# frozen_string_literal: true

# The gem ships mock services so applications can test their syncs without a
# running pub/sub service. They only have to answer what the real services call.
RSpec.describe 'the mock services' do
  describe PubSubModelSync::MockGoogleService do
    let(:service) { described_class.new }

    it 'answers with the same publisher and subscriber' do
      expect(service.publisher('topic')).to be(service.publisher('topic'))
      expect(service.subscriber('sub')).to be(service.subscriber('sub'))
    end

    it 'answers the admin interface' do
      sub_admin = service.subscription_admin

      expect(service.topic_admin).to be(service.topic_admin)
      expect(sub_admin).to be(service.subscription_admin)
      expect(service.topic_admin.create_topic(name: 'topic')).to be true
      expect(sub_admin.create_subscription(name: 'sub', topic: 'topic'))
        .to be true
    end

    it 'answers the resource paths' do
      expect(service.topic_path('name'))
        .to eq('projects/mock-project/topics/name')
      expect(service.subscription_path('name'))
        .to eq('projects/mock-project/subscriptions/name')
    end

    it 'answers the listener interface' do
      subscriber = service.subscriber('sub')
      listener = subscriber.listen

      expect(subscriber.listen).to be(listener)
      expect(listener.start).to be true
      expect(listener.stop.wait!).to be true
      expect(listener.stop!).to be(listener.stop)
    end

    it 'answers publishing' do
      expect(service.publisher('topic').publish('payload', {})).to be true
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
    end

    it 'answers publishing' do
      expect(channel.topic.publish('payload', {})).to be true
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
      producer = service.producer

      expect(producer.produce('payload', {})).to be true
      expect(producer.deliver_messages).to be true
      expect(producer.shutdown).to be true
    end

    it 'answers the consumer interface' do
      consumer = service.consumer

      expect(consumer.subscribe('topic')).to be true
      expect(consumer.each_message).to be true
      expect(consumer.stop).to be true
    end

    it 'answers closing' do
      expect(service.close).to be true
    end
  end
end
