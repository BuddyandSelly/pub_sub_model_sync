# frozen_string_literal: true

# The gem ships mock services so applications can test their syncs without a
# running pub/sub service. They only have to answer what the real services call.
RSpec.describe 'the mock services' do
  describe PubSubModelSync::MockGoogleService do
    let(:service) { described_class.new }

    it 'answers with the same topic' do
      expect(service.topic).to be(service.topic)
      expect(service.create_topic).to be(service.topic)
    end

    it 'answers the listener interface' do
      subscription = service.topic.subscription
      subscriber = subscription.listen

      expect(service.topic.subscribe).to be(subscription)
      expect(subscription.listen).to be(subscriber)
      expect(subscriber.start).to be true
      expect(subscriber.stop.wait!).to be true
      expect(subscriber.stop!).to be(subscriber.stop)
    end

    it 'answers publishing' do
      expect(service.topic.publish('payload', {})).to be true
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
