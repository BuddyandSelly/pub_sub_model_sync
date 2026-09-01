# frozen_string_literal: true

RSpec.describe PubSubModelSync::ServiceKafka do
  let(:msg_attrs) { { klass: 'User', action: 'action' } }
  let(:message_data) { { data: { msg: 'Hello' }, attributes: msg_attrs } }
  # Stands in for Kafka::FetchedMessage. OpenStruct used to be a default gem,
  # Ruby 4.0 no longer ships it.
  let(:kafka_message) { Struct.new(:value, :headers, keyword_init: true) }
  let(:message) do
    kafka_message.new(value: message_data.to_json,
                      headers: { 'service_model_sync' => true })
  end
  let(:invalid_message) do
    kafka_message.new(headers: { 'invalid_partition' => true })
  end
  let(:inst) { described_class.new }
  let(:service) { inst.service }
  let(:producer) { inst.send(:producer) }

  describe 'initializer' do
    it 'connect to pub/sub service' do
      expect(service).not_to be_nil
    end
  end

  describe '.listen_messages' do
    let(:consumer) { PubSubModelSync::MockKafkaService::MockConsumer.new }
    before { allow(service).to receive(:consumer).and_return(consumer) }
    after { inst.listen_messages }
    it 'start consumer' do
      expect(consumer).to receive(:subscribe)
    end
    it 'listening messages' do
      expect(consumer).to receive(:each_message)
    end
  end

  describe '.listen_messages when it goes wrong' do
    it 'lets a shut down through' do
      shut_down = PubSubModelSync::Runner::ShutDown
      allow(inst).to receive(:start_consumer).and_raise(shut_down)

      expect { inst.listen_messages }.to raise_error(shut_down)
    end

    it 'prints any other error' do
      error = 'Connection lost'
      allow(inst).to receive(:start_consumer).and_raise(error)
      allow(inst).to receive(:log)
      expect(inst).to receive(:log).with(include(error), :error)

      inst.listen_messages
    end
  end

  describe '.process_message' do
    let(:message_processor) { PubSubModelSync::MessageProcessor }
    it 'ignore unknown message' do
      expect(message_processor).not_to receive(:new)
      inst.send(:process_message, invalid_message)
    end
    it 'process message' do
      expect(message_processor)
        .to receive(:new).with(message_data[:data], any_args).and_call_original
      inst.send(:process_message, message)
    end
    it 'error processing' do
      error_msg = 'Invalid params'
      allow(message_processor).to receive(:new).and_raise(error_msg)
      expect(inst).to receive(:log).with(include(error_msg), :error)
      inst.send(:process_message, message)
    end
  end

  describe '.publish' do
    it 'produce' do
      settings = hash_including(:topic, :headers)
      data_regex = /"data":{(.*)"attributes":{/
      expect(producer).to receive(:produce).with(match(data_regex), settings)
      inst.publish(message_data[:data], msg_attrs)
    end
    it 'deliver messages' do
      expect(producer).to receive(:deliver_messages)
      inst.publish(message_data[:data], msg_attrs)
    end
    it 'print error when sending message' do
      error = 'Error msg'
      allow(producer).to receive(:produce).and_raise(error)
      allow(inst).to receive(:log)
      expect(inst).to receive(:log).with(include(error), :error)
      inst.publish(message_data[:data], msg_attrs)
    end
  end

  describe '.stop' do
    it 'stop current subscription' do
      inst.send(:start_consumer)
      expect(inst.consumer).to receive(:stop)
      inst.stop
    end

    # xit 'stop producer at exit' do
    #   pending 'TODO: make a test with exit 0 and listen for producer.shutdown'
    # end
  end
end
